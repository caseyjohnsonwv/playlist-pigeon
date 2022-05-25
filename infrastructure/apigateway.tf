resource "aws_api_gateway_rest_api" "apigw" {
  # create api gateway instance
  name = "carrier-pigeon-api-gateway-${var.env_name}"
}

resource "aws_api_gateway_resource" "v1" {
  # create /v1 under api root
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  parent_id   = aws_api_gateway_rest_api.apigw.root_resource_id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "convert" {
  # create /convert under /v1
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "convert"
}

resource "aws_api_gateway_method" "get_convert" {
  # create get method for /convert
  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  resource_id   = aws_api_gateway_resource.convert.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "get_ok" {
  # tell api gateway to return 200 for get requests
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_resource.convert.id
  http_method = aws_api_gateway_method.get_convert.http_method
  status_code = "200"
}

resource "aws_api_gateway_method" "post_convert" {
  # create post method for /convert
  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  resource_id   = aws_api_gateway_resource.convert.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "post_ok" {
  # tell api gateway to return 201 for post requests
  rest_api_id = aws_api_gateway_rest_api.apigw.id
  resource_id = aws_api_gateway_resource.convert.id
  http_method = aws_api_gateway_method.post_convert.http_method
  status_code = "201"
}

resource "aws_api_gateway_integration" "sqs" {
  # tell api gateway how to push to sqs
  rest_api_id             = aws_api_gateway_rest_api.apigw.id
  resource_id             = aws_api_gateway_resource.convert.id
  http_method             = aws_api_gateway_method.post_convert.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.apigw.arn
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:path/${aws_sqs_queue.job_queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"
  }
}

resource "aws_api_gateway_integration_response" "get_ok" {
  # treat all 2xx responses from sqs as 200 ok for api gateway
  rest_api_id       = aws_api_gateway_rest_api.apigw.id
  resource_id       = aws_api_gateway_rest_api.apigw.root_resource_id
  http_method       = aws_api_gateway_method.get_convert.http_method
  status_code       = aws_api_gateway_method_response.get_ok.status_code
  selection_pattern = "^2[0-9][0-9]"

  depends_on = [
    aws_api_gateway_integration.sqs,
    aws_api_gateway_method.post_convert,
  ]
}

resource "aws_api_gateway_integration" "lambda" {
  # tell api gateway how to invoke lambda
  rest_api_id             = aws_api_gateway_rest_api.apigw.id
  resource_id             = aws_api_gateway_resource.convert.id
  http_method             = aws_api_gateway_method.get_convert.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.retrieval.invoke_arn
}

resource "aws_api_gateway_integration_response" "post_ok" {
  # treat all 2xx responses from lambda as 200 ok for api gateway
  rest_api_id       = aws_api_gateway_rest_api.apigw.id
  resource_id       = aws_api_gateway_rest_api.apigw.root_resource_id
  http_method       = aws_api_gateway_method.post_convert.http_method
  status_code       = aws_api_gateway_method_response.post_ok.status_code
  selection_pattern = "^2[0-9][0-9]"

  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_method.get_convert,
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  # create snapshot of gateway config for live deployment
  rest_api_id = aws_api_gateway_rest_api.apigw.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  # create stage to manage versions of deployed api
  rest_api_id   = aws_api_gateway_rest_api.apigw.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "carrier-pigeon-stage-${var.env_name}"
}

resource "aws_iam_role" "apigw" {
  # create role for api gateway to assume
  name = "carrier-pigeon-api-gateway-${var.env_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com",
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "apigw_sqs" {
  # give above role access to sqs
  name = "carrier-pigeon-api-gateway-sqs"
  role = aws_iam_role.apigw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = "${aws_sqs_queue.job_queue.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "apigw_lambda" {
  # give above role access to lambda
  name = "carrier-pigeon-api-gateway-lambda"
  role = aws_iam_role.apigw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "${aws_lambda_function.retrieval.arn}"
      }
    ]
  })
}