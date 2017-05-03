#!/usr/bin/env bash

set -xu

STACK_NAME="${STACK_NAME:-presentation}"
REGION="${REGION:-eu-west-1}"

aws s3 rb \
	--region "${REGION}" \
	"s3://${STACK_NAME}-codepipeline-artifacts" \
	--force

aws ecr delete-repository \
	--region "${REGION}" \
	--repository-name "${STACK_NAME}-myapp" \
	--force

aws cloudformation delete-stack \
	--region "${REGION}" \
    --stack-name "${STACK_NAME}-MyApp-Service"

aws cloudformation wait stack-delete-complete \
	--region "${REGION}" \
	--stack-name "${STACK_NAME}-MyApp-Service"

aws cloudformation delete-stack \
	--region "${REGION}" \
    --stack-name "${STACK_NAME}"

aws cloudformation wait stack-delete-complete \
	--region "${REGION}" \
	--stack-name "${STACK_NAME}"

# Cleanup ACM Certificates
CERT_ARN=$(\
	aws acm list-certificates \
		--region "${REGION}" \
		--query "CertificateSummaryList[?ends_with(DomainName,\`${STACK_NAME}.al-labs.co.uk\`)].CertificateArn" \
		--output text \
)

for arn in ${CERT_ARN} ; do
	aws acm delete-certificate \
		--region "${REGION}" \
		--certificate-arn "${arn}"
done

# Cleanup Los Groups
declare -a LOG_GROUPS=(
	"/aws/codebuild/${STACK_NAME}-myapp"
	"/aws/codebuild/${STACK_NAME}-myapp-image"
	"/aws/lambda/${STACK_NAME}-set-param-store"
	"${STACK_NAME}-ecs"
)

LOG_GROUPS+=(
	$(aws --region "${REGION}" logs describe-log-groups --query "logGroups[?starts_with(logGroupName, \`${STACK_NAME}-TrailLogGroup\`)].logGroupName" --output text)
)
for groupName in "${LOG_GROUPS[@]}" ; do
	aws logs delete-log-group \
		--region "${REGION}" \
		--log-group-name "${groupName}"
done

# Cleanup CloudTrail S3 objects
CT_BUCKET=$(aws s3api list-buckets \
	--region "${REGION}" \
	--query "Buckets[?starts_with(Name, \`${STACK_NAME}-trailbucket\`)].Name" \
	--output text
)
if [ -n "${CT_BUCKET}" ]; then
	aws s3 rb \
		--region "${REGION}" \
		"s3://" \
		--force
fi

# Cleanup Parameter Store
# NOTE: parameter "namespace" are splited using ',' (dot) and so we use it to
# delimit the <STACK_NAME>
SSM_PARAMS=$(aws ssm describe-parameters \
	--region "${REGION}" \
	--query "Parameters[?starts_with(Name, \`${STACK_NAME}.\`)].{Name:Name}" \
	--output text
)
for param in ${SSM_PARAMS} ; do
	aws ssm delete-parameter \
		--region "${REGION}" \
		--name "${param}"
done
