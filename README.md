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
| entrypoint-file     | Path to entry file                                                                     | true     | ""                                           |
| entrypoint-function | Function on the entrypoint-file to handle events                                       | true     | ""                                           |
| memory              | 128 (in MB) to 10,240 (in MB)                                                          | false    | 128                                          |
| env                 | List of environment variables in YML format                                            | false    | CREATE\_BY: alonch/actions-aws-function-python |
| permissions         | List of permissions following Github standard of service: read or write. In YML format | false    | ""                                           |
| artifacts           | This folder will be zip and deploy to Lambda                                           | false    | ""                                           |
| timeout             | Maximum time in seconds before aborting the execution                                  | false    | 3                                            |
| allow-public-access | Generate a public URL. WARNING: ANYONE ON THE INTERNET CAN RUN THIS FUNCTION           | false    | ""                                           |

## Outputs

| Name | Description                                         |
| ---- | --------------------------------------------------- |
| url  | Public accessible URL, if allow-public-access=true |
| arn  | AWS Lambda ARN                                      |

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