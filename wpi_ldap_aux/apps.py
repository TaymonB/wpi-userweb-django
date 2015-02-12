from django.apps import AppConfig

class WPILDAPAuxConfig(AppConfig):

    name = 'wpi_ldap_aux'
    verbose_name = 'WPI LDAP Integration for Auxiliary Authentication'

    def ready(self):
        from wpi_ldap_aux import signals
