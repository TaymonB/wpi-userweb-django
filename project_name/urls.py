from django.conf import settings
from django.conf.urls import patterns, include, url
from django.conf.urls.static import static
from django.contrib import admin
from daeauth import AdminSiteWithExternalAuth

admin.site = AdminSiteWithExternalAuth()
admin.autodiscover()

urlpatterns = patterns('',
    url(r'^admin/', include(admin.site.urls)),
    url(r'^accounts/login/$', 'django_cas_ng.views.login'),
    url(r'^accounts/logout/$', 'django_cas_ng.views.logout'),
)

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
