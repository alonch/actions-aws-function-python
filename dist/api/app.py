import json
import os
import time

def handler(event, context):
    """
    AWS Lambda function that demonstrates persistent storage with EFS

    This function maintains a counter in a file stored on EFS at /mnt/db
    The counter persists across function invocations

    Parameters:
    event (dict): Event data from API Gateway, S3, etc.
    context (LambdaContext): Lambda runtime information

    Returns:
    dict: Response with counter information and filesystem details
    """
    # EFS mount path where we'll store our persistent data
    efs_path = "/mnt/db"
    counter_file = f"{efs_path}/counter.txt"
    log_file = f"{efs_path}/execution_log.txt"

    # Initialize response data
    counter = 0
    is_first_run = False

    try:
        # Check if the EFS directory exists
        if not os.path.exists(efs_path):
            return {
                "statusCode": 500,
                "body": json.dumps({
                    "error": "EFS volume not mounted at /mnt/db",
                    "message": "Please configure the Lambda function with an EFS volume"
                })
            }

        # Read the counter or initialize if this is the first run
        if os.path.exists(counter_file):
            with open(counter_file, "r") as f:
                counter = int(f.read().strip() or "0")
        else:
            is_first_run = True
            # Create directory structure if needed
            os.makedirs(os.path.dirname(counter_file), exist_ok=True)

        # Increment the counter
        counter += 1

        # Write the updated counter
        with open(counter_file, "w") as f:
            f.write(str(counter))

        # Append to the execution log
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime())
        with open(log_file, "a") as f:
            f.write(f"{timestamp} - Function executed (count: {counter})\n")

        # Get file sizes to demonstrate persistence
        counter_size = os.path.getsize(counter_file)
        log_size = os.path.getsize(log_file) if os.path.exists(log_file) else 0

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "message": "Hello from AWS Lambda with EFS persistence!",
                "counter": counter,
                "is_first_execution": is_first_run,
                "filesystem_info": {
                    "counter_file_size_bytes": counter_size,
                    "log_file_size_bytes": log_size,
                    "efs_mounted": True
                },
                "request_id": context.aws_request_id
            })
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "error": str(e),
                "message": "Error accessing EFS volume"
            })
        }