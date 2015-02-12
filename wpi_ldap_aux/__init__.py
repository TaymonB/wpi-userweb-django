from django.conf import settings
import ldap3

default_app_config = 'wpi_ldap_aux.apps.WPILDAPAuxConfig'

authdn, password = settings.WPI_LDAP_AUX_AUTH
server_pool = ldap3.ServerPool(('ldaps://ldapv2back.wpi.edu', 'ldaps://vmldapalt.wpi.edu', 'ldaps://ldapv2.wpi.edu'),
                               pool_strategy=ldap3.FIRST, active=True, exhaust=True)

def populate_from_ldap(user):
    with ldap3.Connection(server_pool, user=authdn, password=password, client_strategy=ldap3.SYNC, read_only=True,
                          raise_exceptions=True) as conn:
        conn.search(search_base='ou=People,dc=wpi,dc=edu', search_filter='(uid={})'.format(user.username),
                    search_scope=ldap3.LEVEL, attributes=('givenName', 'sn', 'mail'), size_limit=1)
        resp, = conn.response
    attrs = resp['attributes']
    user.first_name, = attrs['givenName']
    user.last_name, = attrs['sn']
    email, = attrs['mail']
    local_part, _, domain = email.rpartition('@')
    user.email = '{}@{}'.format(local_part, domain.lower())
    user.save(update_fields=('first_name', 'last_name', 'email'))
