locals {
  # Determine if we should create a queue for worker mode
  create_queue = var.worker == "true"
  queue_name   = "${var.name}-queue-${random_id.suffix.hex}"
}

# Create SQS queue for worker mode
resource "aws_sqs_queue" "worker_queue" {
  count = local.create_queue ? 1 : 0
  name  = local.queue_name

  # Default SQS queue configuration
  visibility_timeout_seconds = var.timeout + 5  # Set slightly higher than Lambda timeout
  message_retention_seconds  = 1209600          # 14 days (maximum)
  receive_wait_time_seconds  = 20               # Enable long polling

  # Add tags for identification
  tags = {
    Name        = local.queue_name
    Environment = "production"
    CreatedBy   = "alonch/actions-aws-function-python"
    WorkerFor   = var.name
  }
}

# Create Lambda event source mapping to connect SQS to Lambda
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  count            = local.create_queue ? 1 : 0
  event_source_arn = aws_sqs_queue.worker_queue[0].arn
  function_name    = aws_lambda_function.function.function_name

  # Configure batch size of 1 as requested
  batch_size = 1

  # Enable the trigger
  enabled = true
}

# Attach SQS permissions to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  count      = local.create_queue ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}