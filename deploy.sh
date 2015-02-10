#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

usage="Usage: $(basename "$0") [-g] [-d project_directory] [-r repository_url] [-b branch] [-p relative_path] db_name db_username db_password"

group_permissions=false
branch=master
relative_path=.

while getopts hgd:r:b:p: OPT; do
  case "$OPT" in
    h)
      echo "$usage"
      exit 0
      ;;
    g)
      group_permissions=true
      ;;
    d)
      project_directory="$OPTARG"
      ;;
    r)
      repository_url="$OPTARG"
      ;;
    b)
      branch="$OPTARG"
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
[[ "${1-x}" = '--' ]] && shift
if [ $# -ne 3 ]; then
  echo "$usage" >&2
  exit 1
fi

if ! hash python3.4 2>/dev/null; then
  cd "$(mktemp -d)"
  curl 'https://www.python.org/ftp/python/3.4.2/Python-3.4.2.tar.xz' | unxz | tar x
  cd Python-3.4.2
  ./configure --prefix="$HOME/.local"
  make install
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.profile"
  fi
fi

[[ -d "${project_directory=$1}" ]] || mkdir "$project_directory"
cd "$project_directory"
project_name="$(basename "$project_directory")"

if [[ -z "${repository_url+x}" ]]; then
  python3.4 -m venv venv
  venv/bin/pip install Django PyMySQL django-admin-external-auth django-cas-ng django-environ django-sslify flipflop pytz
  venv/bin/pip freeze >requirements.txt
  venv/bin/django-admin.py startproject --template='https://github.com/TaymonB/wpi-userweb-django/zipball/master' "$project_name" .
  git init
  git add "$project_name/" manage.py requirements.txt sample.env static/ templates/
  git commit -m "Created Django project $project_name"
  [[ "$branch" = 'master' ]] || git checkout -b "$branch"
else
  git clone "$repository_url" .
  git checkout "$branch"
  python3.4 -m venv venv
  venv/bin/pip install -r requirements.txt
fi

public_html="$(readlink -f ~/public_html)"
site_root="$(readlink -f "$public_html/$relative_path")"
base_url="${site_root/$public_html//~$USER}/"
project_root="$(readlink -f .)"

cat >.env <<EOF
DEBUG=false
DATABASE_URL=mysql://$2:$3@mysql.wpi.edu/$1
BASE_URL=$base_url
ASSETS_ROOT=$site_root
GROUP_PERMISSIONS=$group_permissions
SECRET_KEY=$(</dev/urandom tr -dc [:print:] | head -c 64)
ALLOWED_HOSTS=.wpi.edu
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

cat >"$site_root/$project_name.fcgi" <<EOF
#!$project_root/venv/bin/python
import sys
from flipflop import WSGIServer
sys.path.insert(0, '$project_root')
from $project_name.wsgi import application
WSGIServer(application).run()
EOF

cat >"$site_root/.htaccess" <<EOF
RewriteEngine On
RewriteBase $base_url
AddHandler fastcgi-script .fcgi
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^(.*)\$ $project_name.fcgi/\$1 [QSA,L]
EOF

if $group_permissions; then
  chmod 771 "$site_root" "$site_root/media" "$site_root/static"
  chmod 775 "$site_root/$project_name.fcgi"
  chmod 664 "$site_root/.htaccess"
else
  chmod 711 "$site_root" "$site_root/media" "$site_root/static"
  chmod 755 "$site_root/$project_name.fcgi"
  chmod 644 "$site_root/.htaccess"
fi

git update-index --assume-unchanged manage.py
sed -i "1s|/usr/bin/env python|$project_root/venv/bin/python|" manage.py
chmod +x manage.py

cat >.git/hooks/post-receive <<EOF
#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
read from to branch
[[ "\$branch" = *'$branch' ]] || exit 0
../venv/bin/pip install -r ../requirements.txt
../manage.py migrate --noinput
../manage.py collectstatic --noinput --clear
touch $site_root/$project_name.fcgi
EOF
chmod +x .git/hooks/post-receive

./manage.py migrate --noinput
./manage.py collectstatic --noinput --clear
./manage.py createsuperuser --noinput --username="$USER" --email="$USER@wpi.edu"

DJANGO_SETTINGS_MODULE="$project_name.settings" venv/bin/python <<EOF
import django
django.setup()
from django.contrib.flatpages.models import FlatPage
from django.contrib.sites.models import Site
mysite = Site.objects.get()
mysite.domain = r"""users.wpi.edu$base_url"""
mysite.name = r"""$project_name"""
mysite.save()
homepage = FlatPage(url='/', title='Home Page', content='''
  <div class="container">
    <h1>Home Page</h1>
    <p>Hi! You&rsquo;ve deployed a Django project! You can configure it through the <a href="admin/">admin interface</a>.</p>
  </div>
''')
homepage.save()
homepage.sites.add(mysite)
EOF
