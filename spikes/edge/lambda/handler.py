import json


def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json", "X-Served-By": "new"},
        "body": json.dumps({"servedBy": "new", "path": event.get("rawPath")}),
    }
