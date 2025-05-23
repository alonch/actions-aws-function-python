# GitHub Action for AWS Lambda Python Functions

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Description

This GitHub Action provisions an AWS Lambda function using Python runtime via Terraform

## Inputs

| Name                | Description                                                                            | Required | Default                                      |
| ------------------- | -------------------------------------------------------------------------------------- | -------- | -------------------------------------------- |
| action              | Desired outcome: apply, plan or destroy                                                | false    | apply                                        |
| name                | Function name                                                                          | true     | ""                                           |
| arm                 | Run in ARM compute                                                                     | false    | true                                         |
| python-version      | Python version, Supported versions: 3.8, 3.9, 3.10, 3.11, 3.12                         | false    | 3.11                                         |
| worker              | Enable worker mode with SQS queue                                                      | false    | ""                                           |
| entrypoint-file     | Path to entry file                                                                     | true     | ""                                           |
| entrypoint-function | Function on the entrypoint-file to handle events                                       | true     | ""                                           |
| memory              | 128 (in MB) to 10,240 (in MB)                                                          | false    | 128                                          |
| env                 | List of environment variables in YML format                                            | false    | CREATE\_BY: alonch/actions-aws-function-python |
| permissions         | List of permissions following Github standard of service: read or write. In YML format | false    | ""                                           |
| artifacts           | This folder will be zip and deploy to Lambda                                           | false    | ""                                           |
| timeout             | Maximum time in seconds before aborting the execution                                  | false    | 3                                            |
| allow-public-access | Generate a public URL. WARNING: ANYONE ON THE INTERNET CAN RUN THIS FUNCTION           | false    | ""                                           |
| volume              | Creates an EFS volume and mounts it to /mnt/{volume}. Persists data across invocations | false    | ""                                           |

## Outputs

| Name       | Description                                         |
| ---------- | --------------------------------------------------- |
| url        | Public accessible URL, if allow-public-access=true  |
| arn        | AWS Lambda ARN                                      |
| queue-arn  | ARN of the SQS queue (if worker mode is enabled)    |
| queue-name | Name of the SQS queue (if worker mode is enabled)   |
| queue-url  | URL of the SQS queue (if worker mode is enabled)    |

## Sample Usage

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
    runs-on: ubuntu-latest
    steps:
      - name: Check out repo
        uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: us-east-1
          role-to-assume: ${{ secrets.ROLE_ARN }}
          role-session-name: ${{ github.actor }}
      - uses: alonch/actions-aws-backend-setup@main
        id: backend
        with:
          instance: demo
      - uses: alonch/actions-aws-function-python@main
        with:
          name: actions-aws-function-python-demo
          entrypoint-file: src/app.py
          entrypoint-function: handler
          artifacts: dist
          allow-public-access: true
```

## Using Persistent Storage with EFS

To create a Lambda function with persistent storage, use the `volume` parameter:

```yaml
- uses: alonch/actions-aws-function-python@main
  with:
    name: stateful-lambda-function
    entrypoint-file: src/app.py
    entrypoint-function: handler
    volume: db
    timeout: 10 # Note: min 10 seconds when using EFS
```

This will:
1. Create an EFS file system in your default VPC
2. Mount it to your Lambda function at `/mnt/db`
3. All data written to this path will persist across function invocations

**Note:** Using EFS requires the Lambda to run in a VPC, which can increase cold start times. The minimum timeout when using EFS is 10 seconds.

## Worker Mode with SQS Queue

To create a Lambda function with a worker queue, use the `worker` parameter:

```yaml
- uses: alonch/actions-aws-function-python@main
  id: worker
  with:
    name: worker-lambda
    entrypoint-file: src/app.py
    entrypoint-function: handler
    worker: true
```

This will:
1. Create an SQS queue
2. Configure the Lambda function to process messages from the queue
3. Set up appropriate permissions
4. Provide the queue ARN and name as outputs

**Note:** When using worker mode, your Lambda handler function should expect SQS event payloads.

## Network Integration

This action integrates with [actions-aws-network](https://github.com/realsensesolutions/actions-aws-network) to deploy Lambda functions in custom VPC infrastructure with enhanced security.

### Using Custom Network (Recommended)

When you use the network action before this Lambda action, your functions will be deployed in **private subnets** for better security:

```yaml
- uses: realsensesolutions/actions-aws-network@main
  with:
    action: apply
- uses: alonch/actions-aws-function-python@main
  with:
    name: secure-lambda
    entrypoint-file: src/app.py
    entrypoint-function: handler
    volume: db  # EFS will be created in private subnets
```

### Network Architecture Benefits

When using the network action, your Lambda gets:
- **Private subnets**: `10.0.32.0/20` and `10.0.48.0/20` across multiple AZs
- **NAT Gateway**: For secure internet access from private subnets
- **Pre-configured security groups**: Optimized for private network access
- **Multi-AZ deployment**: High availability and fault tolerance

### Fallback Behavior

If the network action is not used, Lambda functions with EFS will deploy in the **default VPC** with default subnets. This maintains backward compatibility with existing workflows.

## Service Permissions

You can specify AWS service permissions using the `permissions` parameter:

```yaml
- uses: alonch/actions-aws-function-python@main
  with:
    name: lambda-with-permissions
    entrypoint-file: src/app.py
    entrypoint-function: handler
    permissions: |
      s3: read
      dynamodb: write
      sqs: write
```

Supported services and access levels:
- `s3`: `read` or `write`
- `dynamodb`: `read` or `write`
- `sqs`: `read` or `write`

This uses standard AWS managed policies for each service and access level.