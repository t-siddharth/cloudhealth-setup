class Setup
  def bucket_has_policy
    begin
      @s3.get_bucket_policy(@setup_bucket)
      true
    rescue
      false
    end
  end

  def user_has_policy
    begin
      @iam.get_user_policy("CHTRoPolicy", @aws_ro_name)
      true
    rescue
      false
    end
  end

  def bucket_policy
    { "Version" => "2008-10-17",
      "Id" => "Policy1335892530063",
      "Statement" => [
        {
          "Sid" => "Stmt1335892150622",
          "Effect" => "Allow",
          "Principal" => {
            "AWS" => "arn:aws:iam::386209384616:root"
          },
          "Action" => ["s3:GetBucketAcl", "s3:GetBucketPolicy"],
          "Resource" => "arn:aws:s3:::#{@setup_bucket}"
        },
        {
          "Sid" => "Stmt1335892526596",
          "Effect" => "Allow",
          "Principal" => {
            "AWS" => "arn:aws:iam::386209384616:root"
          },
          "Action" => ["s3:PutObject"],
          "Resource" => "arn:aws:s3:::#{@setup_bucket}/*"
        }
      ]
    }
  end
  def aws_ro_policy
    {
      "Statement" => [
        {
          "Effect" => "Allow",
          "Action" => [
            "aws-portal:ViewBilling",
            "aws-portal:ViewUsage",
            "autoscaling:Describe*",
            "cloudformation:ListStacks",
            "cloudformation:ListStackResources",
            "cloudformation:DescribeStacks",
            "cloudformation:DescribeStackEvents",
            "cloudformation:DescribeStackResources",
            "cloudformation:GetTemplate",
            "cloudfront:Get*",
            "cloudfront:List*",
            "cloudwatch:Describe*",
            "cloudwatch:Get*",
            "cloudwatch:List*",
            "dynamodb:DescribeTable",
            "dynamodb:ListTables",
            "ec2:Describe*",
            "elasticache:Describe*",
            "elasticbeanstalk:Check*",
            "elasticbeanstalk:Describe*",
            "elasticbeanstalk:List*",
            "elasticbeanstalk:RequestEnvironmentInfo",
            "elasticbeanstalk:RetrieveEnvironmentInfo",
            "elasticloadbalancing:Describe*",
            "elasticmapreduce:Describe*",
            "elasticmapreduce:List*",
            "iam:List*",
            "iam:Get*",
            "redshift:Describe*",
            "route53:Get*",
            "route53:List*",
            "rds:Describe*",
            "rds:ListTagsForResource",
            "s3:List*",
            "s3:GetBucketTagging",
            "sdb:GetAttributes",
            "sdb:List*",
            "sdb:Select*",
            "ses:Get*",
            "ses:List*",
            "sns:Get*",
            "sns:List*",
            "sqs:GetQueueAttributes",
            "sqs:ListQueues",
            "sqs:ReceiveMessage",
            "storagegateway:List*",
            "storagegateway:Describe*"
          ],
          "Resource" => "*"
        },
        {
          "Effect" => "Allow",
          "Action" => [ "s3:Get*","s3:List*" ],
          "Resource" => [
            "arn:aws:s3:::#{@setup_bucket}",
            "arn:aws:s3:::#{@setup_bucket}/*"
          ]
        }
      ]
    }
  end
end
