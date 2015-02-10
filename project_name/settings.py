"""
Django settings for {{ project_name }} project.

For more information on this file, see
https://docs.djangoproject.com/en/{{ docs_version }}/topics/settings/

For the full list of settings and their values, see
https://docs.djangoproject.com/en/{{ docs_version }}/ref/settings/
"""

import os

from django.utils.six.moves.urllib.parse import urljoin
import environ

root = environ.Path(__file__) - 2
env = environ.Env()
if os.path.exists(root('.env')):
    environ.Env.read_env(root('.env'))

# Development vs. production mode
DEBUG = TEMPLATE_DEBUG = env('DEBUG', bool, False)

# Database
DATABASES = {'default': env.db()}

# URLs where things are served from
base_url = env('BASE_URL', str, '/')
if not base_url.endswith('/'):
    base_url += '/'

# Collecting static files and storing uploaded files
assets_root = env('ASSETS_ROOT', environ.Path, None)
if assets_root is None:
    MEDIA_ROOT = root('media/')
else:
    STATIC_ROOT = assets_root('static/')
    MEDIA_ROOT = assets_root('media/')

# Security
SECRET_KEY = env('SECRET_KEY')
if not DEBUG:
    ALLOWED_HOSTS = env('ALLOWED_HOSTS', list)
SSLIFY_DISABLE = not env('SSLIFY', bool, not DEBUG)

# Internationalization, etc.
LANGUAGE_CODE = env('LANGUAGE_CODE')
TIME_ZONE = env('TIME_ZONE')

# Email
globals().update(env.email_url())
if EMAIL_HOST and EMAIL_HOST != 'localhost':
    DEFAULT_FROM_EMAIL = env('DEFAULT_FROM_EMAIL')
else:
    DEFAULT_FROM_EMAIL = env('DEFAULT_FROM_EMAIL', str, 'webmaster@localhost')

# System administration
ADMINS = tuple(tuple(admin.split(':', 1)) for admin in env('ADMINS', list, ()))
MANAGERS = env('MANAGERS', list, ADMINS)
if isinstance(MANAGERS, list):
    MANAGERS = tuple(tuple(manager.split(':', 1)) for manager in MANAGERS)
SERVER_EMAIL = env('SERVER_EMAIL', str,
                   'root@localhost' if DEFAULT_FROM_EMAIL == 'webmaster@localhost' else DEFAULT_FROM_EMAIL)

# Sites framework
SITE_ID = env('SITE_ID', int, 1)

# CAS
CAS_SERVER_URL = env('CAS_SERVER_URL')

# The rest of this stuff doesn't depend on deployment settings.

INSTALLED_APPS = (
    'django.contrib.admin.apps.SimpleAdminConfig',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'django.contrib.sites',
    'django.contrib.flatpages',
)

MIDDLEWARE_CLASSES = (
    'sslify.middleware.SSLifyMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.auth.middleware.SessionAuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'django.contrib.flatpages.middleware.FlatpageFallbackMiddleware',
)

AUTHENTICATION_BACKENDS = (
    # Uncomment this if you're adding support for non-CAS authentication
    # 'django.contrib.auth.backends.ModelBackend',
    'django_cas_ng.backends.CASBackend',
)

ROOT_URLCONF = '{{ project_name }}.urls'
WSGI_APPLICATION = '{{ project_name }}.wsgi.application'

TEMPLATE_DIRS = (
    root('templates'),
)

STATICFILES_DIRS = (
    root('static'),
)

CSRF_COOKIE_PATH = LANGUAGE_COOKIE_PATH = SESSION_COOKIE_PATH = CAS_REDIRECT_URL = base_url
STATIC_URL = urljoin(base_url, 'static/')
MEDIA_URL = urljoin(base_url, 'media/')

FILE_UPLOAD_PERMISSIONS = 0o644
FILE_UPLOAD_DIRECTORY_PERMISSIONS = 0o711

LOGIN_URL = 'django_cas_ng.views.login'
LOGOUT_URL = 'django_cas_ng.views.logout'

CSRF_COOKIE_SECURE = SESSION_COOKIE_SECURE = not DEBUG

USE_I18N = USE_L10N = USE_TZ = True

TEST_RUNNER = 'django.test.runner.DiscoverRunner'
