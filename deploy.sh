#!/usr/bin/env bash

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
cd "$work_tree_dir"
repository_dir="$(readlink -f "${repository_dir-../$(basename "$work_tree_dir").git}")"
[[ -d "$repository_dir" ]] || mkdir "$repository_dir"

if [[ -n "${origin_url-}" ]]; then
  git clone --bare "$origin_url" "$repository_dir"
  export GIT_DIR="$repository_dir" GIT_WORK_TREE=.
  git checkout "$branch"
  project_name="$(sed 's/^\s\s*os\.environ\.setdefault("DJANGO_SETTINGS_MODULE", "\([[:alpha:]_][[:alnum:]_]*\)\.settings")$/\1/;t;d' manage.py)"
  python3.4 -m venv venv
  venv/bin/pip install -r requirements.txt
else
  python3.4 -m venv venv
  venv/bin/pip install Django PyMySQL django-admin-external-auth django-cas-ng django-environ django-sslify flipflop ldap3 pytz
  venv/bin/pip freeze >requirements.txt
  project_name="$(basename "$work_tree_dir")"
  venv/bin/django-admin.py startproject --template=https://github.com/TaymonB/wpi-userweb-django/zipball/master "$project_name" .
  git init --bare "$repository_dir"
  export GIT_DIR="$repository_dir" GIT_WORK_TREE=.
  git add "$project_name/" .gitignore manage.py media/ requirements.txt sample.env static/ templates/
  git commit -m "Created Django project $project_name"
  [[ "$branch" = 'master' ]] || git checkout -b "$branch"
fi

public_html="$(readlink -f ~/public_html)"
site_root="$(readlink -f "$public_html/$relative_path")"
base_url="${site_root/#$public_html//~$USER}/"

cat >.env <<EOF
DEBUG=False
DATABASE_URL=mysql://$2:$3@mysql.wpi.edu/$1
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

superdir="$site_root"
while [[ "$superdir" != '/' ]]; do
  superdir="$(dirname "$superdir")"
  [[ "$(ls -ld "$superdir" | cut -d ' ' -f 3)" = "$USER" ]] && chmod a+x "$superdir"
done

[[ -d "$site_root" ]] || mkdir "$site_root"
mkdir "$site_root/media" "$site_root/static"

deploy_name="$(basename "$site_root")"
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

cat >"$repository_dir/hooks/post-receive" <<EOF
#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
read from to branch
[[ "\$branch" = *'$branch' ]] || exit 0
GIT_WORK_TREE='$work_tree_dir' git checkout --force '$branch'
cd '$work_tree_dir'
venv/bin/pip install -r requirements.txt
venv/bin/python manage.py migrate --noinput
venv/bin/python manage.py collectstatic --noinput --clear
touch '$site_root/$deploy_name.fcgi'
EOF
chmod +x "$repository_dir/hooks/post-receive"

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
