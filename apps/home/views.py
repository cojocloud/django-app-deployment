from django.http import JsonResponse


def index(request):
    return JsonResponse({"message": "Django app is running", "version": "1.0.0"})
