#!/usr/bin/env bash

(

set -o errexit
set -o pipefail
set -o nounset

usage='Usage: deploy.sh [-o origin_url] [-b branch] [-w work_tree_dir] [-r repository_dir] [-p relative_path] db_name db_username db_password'

branch=master
relative_path=.

while getopts o:b:w:r:p: OPT; do
  case "$OPT" in
    o)
      origin_url="$OPTARG"
      ;;
    b)
      branch="$OPTARG"
      ;;
    w)
      work_tree_dir="$OPTARG"
      ;;
    r)
      repository_dir="$OPTARG"
      ;;
    p)
      relative_path="$OPTARG"
      ;;
    \?)
      echo "$usage" >&2
      exit 1
      ;;
  esac
done
shift $(($OPTIND-1))
[[ "${1-}" = '--' ]] && shift
if [ $# -ne 3 ]; then
  echo "$usage" >&2
  exit 1
fi

if ! hash python3.4; then
  cd "$(mktemp -d)"
  curl https://www.python.org/ftp/python/3.4.2/Python-3.4.2.tar.xz | unxz | tar x
  cd Python-3.4.2
  ./configure --prefix="$HOME/.local"
  make install
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >>~/.profile
  fi
fi

work_tree_dir="$(readlink -f "${work_tree_dir-$1}")"
[[ -d "$work_tree_dir" ]] || mkdir "$work_tree_dir"
repository_dir="$(readlink -f "${repository_dir-$work_tree_dir/../$(basename "$work_tree_dir").git}")"
cd "$work_tree_dir"

if [[ -n "${origin_url-}" ]]; then
  git clone --bare "$origin_url" "$repository_dir"
  export GIT_DIR="$repository_dir" GIT_WORK_TREE=.
  git checkout --force "$branch"
  python3.4 -m venv venv
  venv/bin/pip install -r requirements.txt
elif git rev-parse --resolve-git-dir "$repository_dir"; then
  export GIT_DIR="$repository_dir" GIT_WORK_TREE=.
  git checkout --force "$branch"
  python3.4 -m venv venv
  venv/bin/pip install -r requirements.txt
else
  python3.4 -m venv venv
  venv/bin/pip install Django PyMySQL django-admin-external-auth django-cas-dev-server django-cas-ng django-environ django-sslify flipflop ldap3 pytz
  venv/bin/pip freeze >requirements.txt
  venv/bin/django-admin.py startproject --template=https://github.com/TaymonB/wpi-userweb-django/zipball/master "$(basename "$work_tree_dir")" .
  git init --bare "$repository_dir"
  export GIT_DIR="$repository_dir" GIT_WORK_TREE=.
  git add .
  git commit -m "Created Django project with wpi-userweb-django"
  [[ "$branch" = 'master' ]] || git checkout -b "$branch"
fi

password="$(dd if=/dev/urandom bs=48 count=1 | base64 | tr '+/' '-_')"
mysql --host=mysql.wpi.edu --user="$2" --password="$3" --execute="SET PASSWORD = PASSWORD('$password')" "$1"

public_html="$(readlink -f ~/public_html)"
site_root="$(readlink -f "$public_html/$relative_path")"
base_url="${site_root/#$public_html//~$USER}/"

cat >.env <<EOF
DEBUG=False
DATABASE_URL=mysql://$2:$password@mysql.wpi.edu/$1
BASE_URL=$base_url
ASSETS_ROOT=$site_root
SECRET_KEY=$(dd if=/dev/urandom bs=48 count=1 | base64)
ALLOWED_HOSTS=users.wpi.edu
LANGUAGE_CODE=en-us
TIME_ZONE=America/New_York
EMAIL_URL=smtp://localhost
DEFAULT_FROM_EMAIL=$USER@wpi.edu
ADMINS=$(getent passwd "$USER" | cut -d : -f 5):$USER@wpi.edu
CAS_SERVER_URL=https://cas.wpi.edu/cas/
EOF

project_name="$(venv/bin/python manage.py shell <<EOF | grep '@' | cut -d '@' -f 2
import os
print('@' + os.environ['DJANGO_SETTINGS_MODULE'].rpartition('.')[0])
EOF
)"

superdir="$site_root"
while [[ "$superdir" != '/' ]]; do
  superdir="$(dirname "$superdir")"
  [[ "$(ls -ld "$superdir" | cut -d ' ' -f 3)" = "$USER" ]] && chmod a+x "$superdir"
done

[[ -d "$site_root" ]] || mkdir "$site_root"
mkdir "$site_root/media" "$site_root/static"

if [[ "$site_root" -ef "$public_html" ]]; then
  deploy_name="$USER"
else
  deploy_name="$(basename "$site_root")"
fi
cat >"$site_root/$deploy_name.fcgi" <<EOF
#!$work_tree_dir/venv/bin/python
import sys
from flipflop import WSGIServer
sys.path.insert(0, '$work_tree_dir')
from $project_name.wsgi import application
WSGIServer(application).run()
EOF

cat >"$site_root/.htaccess" <<EOF
RewriteEngine On
RewriteBase $base_url
AddHandler fastcgi-script .fcgi
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^(.*)\$ $deploy_name.fcgi/\$1 [QSA,L]
EOF

chmod 711 "$site_root" "$site_root/media" "$site_root/static"
chmod 755 "$site_root/$deploy_name.fcgi"
chmod 644 "$site_root/.htaccess"

if [[ ! -f "$repository_dir/hooks/post-receive" ]]; then
  cat >"$repository_dir/hooks/post-receive" <<EOF
#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
read from to branch
EOF
  chmod +x "$repository_dir/hooks/post-receive"
fi
cat >>"$repository_dir/hooks/post-receive" <<EOF
if [[ "\$branch" = *'$branch' ]]; then
  GIT_WORK_TREE='$work_tree_dir' git checkout --force '$branch'
  cd '$work_tree_dir'
  venv/bin/pip install -r requirements.txt
  venv/bin/python manage.py migrate --noinput
  venv/bin/python manage.py collectstatic --noinput --clear
  touch '$site_root/$deploy_name.fcgi'
fi
EOF

venv/bin/python manage.py migrate --noinput
venv/bin/python manage.py collectstatic --noinput --clear

DJANGO_SETTINGS_MODULE="$project_name.settings" venv/bin/python <<EOF
import django
django.setup()
from django.apps import apps
from django.conf import settings
if apps.is_installed('django.contrib.auth') and settings.AUTH_USER_MODEL == 'auth.User':
    from django.contrib.auth.models import User
    if not User.objects.filter(username=r"""$USER""").exists():
        from wpi_ldap_aux import populate_from_ldap
        populate_from_ldap(User.objects.create_superuser(r"""$USER""", None, None))
if apps.is_installed('django.contrib.sites'):
    from django.contrib.sites.models import Site
    mysite = Site.objects.get()
    mysite.domain = r"""users.wpi.edu$base_url"""
    mysite.name = r"""$project_name"""
    mysite.save()
    if apps.is_installed('django.contrib.flatpages'):
        from django.contrib.flatpages.models import FlatPage
        homepage = FlatPage(url='/', title='Home Page', content='<div class="container"><h1>Home Page</h1><p>Hi! You&rsquo;ve deployed a Django project! You can configure it through the <a href="admin/">admin interface</a>.</p></div>')
        homepage.save()
        homepage.sites.add(mysite)
EOF

)
