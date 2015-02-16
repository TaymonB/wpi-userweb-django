#!/usr/bin/env python

from __future__ import print_function

import os
import sys

if __name__ == '__main__':
    venv_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'venv'))
    venv_executable = os.path.join(venv_dir, 'bin/python')

    if sys.executable != venv_executable:
        if not os.path.exists(venv_dir):
            import venv
            venv.create(venv_dir, use_symlinks=os.name != 'nt', with_pip=True)
        os.execv(venv_executable, [venv_executable] + sys.argv)

    else:
        import pip
        pip.main(['install', '-r', 'requirements.txt'])
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', '{{ project_name }}.settings')

        import shutil
        shutil.copy(os.path.join(os.path.dirname(__file__), 'sample.env'),
                    os.path.join(os.path.dirname(__file__), '.env'))

        import django
        django.setup()

        from django.core.management import call_command, execute_from_command_line
        call_command('migrate')
        execute_from_command_line(['', 'casdevmanage', 'migrate'])

        import getpass
        from django.six import PY3
        if PY3:
            raw_input = input
        username = password = ''
        while not username:
            username = raw_input('Enter your WPI username: ')
        print('Your WPI password will not be sent unencrypted or to any third party.')
        while not password:
            password = getpass.getpass('Enter your WPI password: ')
        print('You will now be asked to create a new local password.')
        execute_from_command_line(['', 'casdevmanage', 'createsuperuser', '--username=' + username,
                                   '--email={}@wpi.edu'.format(username)])

        from django.contrib.auth.models import User
        import ldap3
        import wpi_ldap_aux
        with ldap3.Connection(wpi_ldap_aux.server_pool, client_strategy=ldap3.SYNC, read_only=True,
                              raise_exceptions=True) as conn:
            conn.search(search_base='ou=People,dc=wpi,dc=edu', search_filter='(uid={})'.format(username),
                        search_scope=ldap3.LEVEL, size_limit=1)
            resp, = conn.response
        wpi_ldap_aux.authdn = resp['dn']
        wpi_ldap_aux.password = password
        wpi_ldap_aux.populate_from_ldap(User.objects.create_superuser(username, None, None))
        with open(os.path.join(os.path.dirname(__file__), '.env'), 'a') as f:
            f.write('WPI_LDAP_AUX_AUTH={}:{}\n'.format(wpi_ldap_aux.authdn, password))

        from django.contrib.flatpages.models import FlatPage
        from django.contrib.sites.models import Site
        homepage = FlatPage(url='/', title='Home Page', content='<div class="container"><h1>Home Page</h1><p>\
Hi! You&rsquo;ve deployed a Django project! You can configure it through the <a href="admin/">admin interface</a>.\
</p></div>')
        homepage.save()
        homepage.sites.add(Site.objects.get())
