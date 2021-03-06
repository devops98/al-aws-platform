#!/usr/bin/env bash

set -xu

PREFIX="${PREFIX:-presentation}"
STACK_NAME="${STACK_NAME:-$(aws cloudformation list-exports --query "Exports[?Name=='${PREFIX}-stack-name'].Value" --output text)}"
REGION="${REGION:-eu-west-1}"
MASTER="${MASTER:-false}"

# If MASTER is true then delete the Service Catalog stacks
if [ "${MASTER}" == false ]
then
# Delete CLOUD PLATFORM Product Stack Stuff
	aws ecr delete-repository \
		--region "${REGION}" \
		--repository-name "${PREFIX}-containerimage" \
		--force

	aws cloudformation delete-stack \
		--region "${REGION}" \
		--stack-name "${PREFIX}-ContainerApp"

	aws cloudformation wait stack-delete-complete \
		--region "${REGION}" \
		--stack-name "${PREFIX}-ContainerApp"

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
			--query "CertificateSummaryList[?ends_with(DomainName,\`${PREFIX}.al-labs.co.uk\`)].CertificateArn" \
			--output text \
	)

	for arn in ${CERT_ARN} ; do
		aws acm delete-certificate \
			--region "${REGION}" \
			--certificate-arn "${arn}"
	done

	# Cleanup Log Groups
	declare -a LOG_GROUPS=(
		"/aws/cloudtrail/${PREFIX}"
		"/aws/codebuild/${PREFIX}-build"
		"/aws/codebuild/${PREFIX}-ecs-image"
		"/aws/codebuild/${PREFIX}-test"
		"/aws/codebuild/${PREFIX}-integration-test"
		"/aws/codebuild/${PREFIX}-application"
		"/aws/codebuild/${PREFIX}-kibana"
		"/aws/codebuild/${PREFIX}-CodeBuildLambda"
		"/aws/lambda/${PREFIX}-es-snapshots"
		"/aws/lambda/${PREFIX}-set-param-store"
		"/aws/lambda/${PREFIX}-log-streamer"
		"/aws/lambda/${PREFIX}-SnapshotLambda"
		"/aws/lambda/${PREFIX}-elblogs-to-cw-migration"
		"/aws/lambda/${PREFIX}-log-migration"
		"/aws/lambda/${PREFIX}-TamperLambda"
		"/aws/lambda/${PREFIX}-slack-notifications"
		"/aws/lambda/${PREFIX}-AutoCleanup"
		"/aws/lambda/${PREFIX}-SC-SyncLambda"
		"/aws/lambda/${PREFIX}-add-target-with-transform"
		"${PREFIX}-ecs"
		"${PREFIX}-applog"
		"${PREFIX}-cloudinitoutput"
		"${PREFIX}-elblog"
		"${PREFIX}-syslog"
		"${PREFIX}-vpcflowlog"
		"${PREFIX}-db-debug"
		"${PREFIX}-db-httpapi"
		"${PREFIX}-db-security"
		"${PREFIX}-db-cloudinitoutput"
	)

	LOG_GROUPS+=(
		$(aws --region "${REGION}" logs describe-log-groups --query "logGroups[?starts_with(logGroupName, \`${PREFIX}-TrailLogGroup\`)].logGroupName" --output text)
	)
	for groupName in "${LOG_GROUPS[@]}" ; do
		aws logs delete-log-group \
			--region "${REGION}" \
			--log-group-name "${groupName}"
	done

	# Cleanup CloudTrail S3 objects
	declare -a S3_BUCKETS=(
		"${PREFIX}-codepipeline-artifacts"
		"${PREFIX}-artifacts"
		"${PREFIX}-elb-logs"
		"${PREFIX}-es-snapshots"
		"${PREFIX}-logs"
		"${PREFIX}-snapshots"
	)

	S3_BUCKETS+=(
		$(aws s3api list-buckets \
			--region "${REGION}" \
			--query "Buckets[?starts_with(Name, \`${PREFIX}-trailbucket\`)].Name" \
			--output text
		)
	)
	for bucketName in "${S3_BUCKETS[@]}"; do
		aws s3 rb \
			--region "${REGION}" \
			"s3://${bucketName}" \
			--force
	done

	# Cleanup Parameter Store
	# NOTE: parameter "namespace" are splited using '/' (slash) and so we use it to
	# delimit the <STACK_NAME>

	# NOTE: The Parameter store lambda now self cleans the parameter store on delete. This delete operation is no longer needed in the cleanup script.

	# SSM_PARAMS=$(aws ssm describe-parameters \
	# 	--region "${REGION}" \
	# 	--query "Parameters[?starts_with(Name, \`${STACK_NAME}.\`)].{Name:Name}" \
	# 	--output text
	# )
	# for param in ${SSM_PARAMS} ; do
	# 	aws ssm delete-parameter \
	# 		--region "${REGION}" \
	# 		--name "${param}"
	# done

else

# Delete Service Catalog Master Stack Stuff

	aws cloudformation delete-stack \
		--region "${REGION}" \
		--stack-name "${STACK_NAME}-sync-lambda"

	aws cloudformation wait stack-delete-complete \
		--region "${REGION}" \
		--stack-name "${STACK_NAME}--sync-lambda"

	aws cloudformation delete-stack \
		--region "${REGION}" \
		--stack-name "${STACK_NAME}"

	aws cloudformation wait stack-delete-complete \
		--region "${REGION}" \
		--stack-name "${STACK_NAME}"

	# Cleanup Log Groups
	declare -a LOG_GROUPS=(
		"/aws/codebuild/${STACK_NAME}-CodeBuildLambda"
		"/aws/lambda/${STACK_NAME}-AutoCleanup"
		"/aws/lambda/${STACK_NAME}-SC-SyncLambda"
	)

	for groupName in "${LOG_GROUPS[@]}" ; do
		aws logs delete-log-group \
			--region "${REGION}" \
			--log-group-name "${groupName}"
	done

	# Cleanup S3 Buckets
	declare -a S3_BUCKETS=(
		"${STACK_NAME}-artifacts"
	)

	for bucketName in "${S3_BUCKETS[@]}"; do
		aws s3 rb \
			--region "${REGION}" \
			"s3://${bucketName}" \
			--force
	done

	PORTFOLIO=$(aws servicecatalog list-portfolios --region "${REGION}" --query "PortfolioDetails[?DisplayName=='ALCloud'].Id" --output text)

	# Disassociate Products and Delete them

	PRODUCTS=$(aws servicecatalog search-products-as-admin --portfolio-id "${PORTFOLIO}" --region "${REGION}" --query "ProductViewDetails[].ProductViewSummary.ProductId" --output text)

	for product in ${PRODUCTS} ; do
		aws servicecatalog disassociate-product-from-portfolio \
			--portfolio-id "${PORTFOLIO}" \
			--region "${REGION}" \
			--product-id "${product}"
	done

	for product in ${PRODUCTS} ; do
		aws servicecatalog delete-product \
			--region "${REGION}" \
			--id "${product}"
	done


	# Delete Constraints

	CONSTRAINTS=$(aws servicecatalog list-constraints-for-portfolio --portfolio-id "${PORTFOLIO}" --region "${REGION}" --query "ConstraintDetails[].ConstraintId" --output text)

	for constraint in ${CONSTRAINTS} ; do
		aws servicecatalog delete-constraint \
			--region "${REGION}" \
			--id "${constraint}"
	done


	# Disassociate Principals

	PRINCIPALS=$(aws servicecatalog list-principals-for-portfolio --portfolio-id "${PORTFOLIO}" --region "${REGION}" --query "Principals[].PrincipalARN" --output text)

	for principal in ${PRINCIPALS} ; do
		aws servicecatalog disassociate-principal-from-portfolio \
			--portfolio-id "${PORTFOLIO}" \
			--region "${REGION}" \
			--principal-arn "${principal}"
	done


	# Finally delete the Portfolio Itself
	aws servicecatalog delete-portfolio --id "${PORTFOLIO}" --region "${REGION}"

fi
