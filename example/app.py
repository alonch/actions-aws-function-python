import json

def handler(event, context):
    """
    Sample AWS Lambda function handler

    Parameters:
    event (dict): Event data from API Gateway, S3, etc.
    context (LambdaContext): Lambda runtime information

    Returns:
    dict: Response object for API Gateway or other AWS services
    """
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({
            "message": "Hello from AWS Lambda Python function!"
        })
    }