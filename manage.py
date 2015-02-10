#!/usr/bin/env python

import os
import sys

if __name__ == '__main__':
    venv_executable = os.path.abspath(os.path.join(os.path.dirname(__file__), 'venv/bin/python'))
    if sys.executable != venv_executable:
        os.execv(venv_executable, [venv_executable] + sys.argv)
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', '{{ project_name }}.settings')
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
