resource "aws_sfn_state_machine" "create_step_function_netsuite" {
  name     = "netsuite-glujobs-orchestration"
  role_arn = aws_iam_role.create_iam_role_stepfunction_netsuite.arn

  definition = jsonencode(
    {
      "StartAt" : "start customer ingestion",
      "States" : {
        "start customer ingestion" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::glue:startJobRun",
          "Parameters" : {
            "JobName" : "netsuite-get-customer"
          },
          "End" : true
        }
      }
    }
  )
}



resource "aws_iam_role" "create_iam_role_stepfunction_netsuite" {
  name = "netsuite-stepfunction-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "states.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "glue_full_access_to_stepfunction" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  role       = aws_iam_role.create_iam_role_stepfunction_netsuite.name
}

resource "aws_cloudwatch_event_rule" "event_rule" {
  name                = "netsuite-stepfuntion-hourly-run" # Replace with your desired rule name
  description         = "Event rule for stepfuntion"
  schedule_expression = "cron(30 * * * ? *)" # Replace with your desired schedule expression, run hourly at 30min

}

resource "aws_cloudwatch_event_target" "stepfunctions_target" {
  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = "netsuite-glujobs-orchestration"
  arn       = aws_sfn_state_machine.create_step_function_netsuite.arn
  role_arn  = aws_iam_role.create_iam_role_event_netsuite.arn
}

resource "aws_iam_role" "create_iam_role_event_netsuite" {
  name = "netsuite-event-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "events.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "stepfunction_full_access_to_eventrule" {
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
  role       = aws_iam_role.create_iam_role_event_netsuite.name
}