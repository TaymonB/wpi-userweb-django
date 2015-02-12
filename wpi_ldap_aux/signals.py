from django.dispatch import receiver
from django_cas_ng.signals import cas_user_authenticated

from wpi_ldap_aux import populate_from_ldap

@receiver(cas_user_authenticated, dispatch_uid='wpi_ldap_aux.signals.populate_from_ldap_on_create')
def populate_from_ldap_on_create(sender, **kwargs):
    if kwargs['created']:
        populate_from_ldap(kwargs['user'])
