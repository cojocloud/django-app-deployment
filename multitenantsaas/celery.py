import os
from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "multitenantsaas.settings")

app = Celery("multitenantsaas")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
