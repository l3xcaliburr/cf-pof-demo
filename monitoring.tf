# =============================================================================
# MANAGEMENT SERVER HEALTH MONITORING
# =============================================================================

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "management_alerts" {
  name = "poc-management-server-alerts"

  tags = merge(var.common_tags, {
    Name    = "poc-management-alerts"
    Purpose = "monitoring"
  })
}

# SNS Topic Subscription (only if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.management_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Alarms for Management Server Instance State (Simple POC monitoring)
resource "aws_cloudwatch_metric_alarm" "management_instance_stopped" {
  count = length(module.management_server.instance_id)

  alarm_name          = "poc-management-server-${count.index + 1}-stopped"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "ALERT: Management server ${count.index + 1} has been stopped or is failing - POC Demo"
  alarm_actions       = [aws_sns_topic.management_alerts.arn]
  ok_actions          = [aws_sns_topic.management_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = module.management_server.instance_id[count.index]
  }

  tags = merge(var.common_tags, {
    Name    = "poc-management-server-${count.index + 1}-stopped"
    Purpose = "poc-demo-monitoring"
  })
} 