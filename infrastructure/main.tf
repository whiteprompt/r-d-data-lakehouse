terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.74.0"
    }
  }
}

provider "aws" {
  region = "${var.region}"
}

data "aws_kms_alias" "kms_encryption" {
  name = "alias/aws/s3"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.s3_bucket_name}"
  acl    = "private"
}

resource "aws_glue_catalog_database" "aws_glue_database" {
  name = "${var.app_name}-db"
}

// More detail configuration of parameters at https://www.terraform.io/docs/providers/aws/r/glue_catalog_table.html
resource "aws_glue_catalog_table" "aws_glue_table" {
  name          = "tbl-${var.app_name}"
  database_name = "${aws_glue_catalog_database.aws_glue_database.name}"

  parameters = {
    EXTERNAL          = "TRUE"
    "classification"  = "parquet"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/tbl-${var.app_name}/"
    input_format  = "${var.storage_input_format}"
    output_format = "${var.storage_output_format}"

    ser_de_info {
      name                  = "${var.serde_name}"
      serialization_library = "${var.serde_library}"

      parameters = {
        "serialization.format" = 1
        "parquet.compression"  = "SNAPPY"
      }
    }

    columns {
        name = "uuid"
        type = "string"
      }

    columns {
        name = "event_date"
        type = "string"
      }

    columns {
        name = "status"
        type = "string"
      }

    columns {
        name = "name"
        type = "string"
      }

    columns {
        name = "last_name"
        type = "string"
      }

    columns {
        name = "email"
        type = "string"
      }

    columns {
        name = "phone"
        type = "string"
      }
  }
}

resource "aws_cloudwatch_log_group" "log_group_kinesis" {
  name = "${var.cloudwatch_log_group_name}"
  tags = {
    EnvType = "${var.env_type}"
    Project = "${var.project_name}"
    Client  = "${var.client_name}"
  }
}

resource "aws_cloudwatch_log_stream" "log_stream_kinesis" {
  name           = "${var.cloudwatch_log_stream_name}"
  log_group_name = aws_cloudwatch_log_group.log_group_kinesis.name
}

resource "aws_kinesis_stream" "kinesis_stream" {
  name             = "${var.app_name}-stream"
  shard_count      = "${var.shard_count}"
  retention_period = "${var.retention_period}"

  //shard_level_metrics = "${var.shard_level_metrics}"

  tags = {
    EnvType = "${var.env_type}"
    Project = "${var.project_name}"
    Client  = "${var.client_name}"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "firehose_stream" {
  name        = "${var.app_name}_delivery_stream"
  destination = "extended_s3"

  tags = {
    EnvType = "${var.env_type}"
    Project = "${var.project_name}"
    Client  = "${var.client_name}"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = "${aws_kinesis_stream.kinesis_stream.arn}"
    role_arn           = "${aws_iam_role.firehose_role.arn}"
  }

  //refer the more s3 configuration at https://docs.aws.amazon.com/firehose/latest/APIReference/API_ExtendedS3DestinationConfiguration.html
  extended_s3_configuration {
    role_arn            = "${aws_iam_role.firehose_role.arn}"
    bucket_arn          = "${aws_s3_bucket.bucket.arn}" 
    buffer_size         = 128
    buffer_interval     = 120
    error_output_prefix = "${var.s3_error_output_prefix}"
    prefix              = "${var.s3_prefix}"
    s3_backup_mode      = "${var.s3_backup_mode}"
    //kms_key_arn         = "${data.aws_kms_alias.kms_encryption.arn}"

    cloudwatch_logging_options {
      enabled         = "${var.cloudwatch_logging_enabled}"
      log_group_name  = "${var.cloudwatch_log_group_name}"
      log_stream_name = "${var.cloudwatch_log_stream_name}"
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          hive_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }

      schema_configuration {
        database_name = "${aws_glue_catalog_table.aws_glue_table.database_name}"
        role_arn      = "${aws_iam_role.firehose_role.arn}"
        table_name    = "${aws_glue_catalog_table.aws_glue_table.name}"
        region        = "${var.region}"
      }
    }

    s3_backup_configuration {
      role_arn           = "${aws_iam_role.firehose_role.arn}"
      bucket_arn         = "${aws_s3_bucket.bucket.arn}"
      prefix              = "source/"
    }
  }
}