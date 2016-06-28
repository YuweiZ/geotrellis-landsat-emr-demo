export AWS_DEFAULT_REGION := us-east-1
export S3_URI := s3://geotrellis-test/emr
export EC2_KEY := geotrellis-cluster
export SUBNET_ID := subnet-c5fefdb1
export NAME := Landsat Demo
export MASTER_INSTANCE:=m3.xlarge
export MASTER_PRICE := 0.5
export MASTER_MEMORY := 10G
export WORKER_INSTANCE:=m3.2xlarge
export WORKER_COUNT := 5
export WORKER_PRICE := 0.5
export EXECUTOR_MEMORY := 9500M
export EXECUTOR_CORES := 4
export YARN_OVERHEAD := 700
export USE_SPOT:=true

# Japan typhoon
export LAYER_NAME := japan-typhoon
export START_DATE := 2015-07-01
export END_DATE := 2015-11-30
export BBOX := 135.35,33.23,143.01,41.1
export MAX_CLOUD_COVERAGE := 20.0

SERVER_ASSEMBLY := server/target/scala-2.10/server-assembly-0.1.0.jar
INGEST_ASSEMBLY := ingest/target/scala-2.10/ingest-assembly-0.1.0.jar
SCRIPT_RUNNER := s3://elasticmapreduce/libs/script-runner/script-runner.jar

ifeq ($(USE_SPOT),true)
MASTER_BID_PRICE:=BidPrice=${MASTER_PRICE},
WORKER_BID_PRICE:=BidPrice=${WORKER_PRICE},
endif

ifdef COLOR
COLOR_TAG=--tags Color=${COLOR}
endif

ifndef CLUSTER_ID
CLUSTER_ID=$(shell if [ -e "cluster-id.txt" ]; then cat cluster-id.txt; fi)
endif

rwildcard=$(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $(subst *,%,$2),$d))

${SERVER_ASSEMBLY}: $(call rwildcard, server/src, *.scala) server/build.sbt
	./sbt "project server" assembly -no-colors
	@touch -m ${SERVER_ASSEMBLY}

${INGEST_ASSEMBLY}: $(call rwildcard, ingest/src, *.scala) ingest/build.sbt
	./sbt "project ingest" assembly -no-colors
	@touch -m ${INGEST_ASSEMBLY}

viewer/site.tgz: $(call rwildcard, viewer/components, *.js)
	@cd viewer && npm install &&npm run build
	tar -czf viewer/site.tgz -C viewer/dist .

upload-code: ${SERVER_ASSEMBLY} ${INGEST_ASSEMBLY} scripts/emr/* viewer/site.tgz
	@aws s3 cp viewer/site.tgz ${S3_URI}/
	@aws s3 cp scripts/emr/bootstrap-demo.sh ${S3_URI}/
	@aws s3 cp scripts/emr/bootstrap-geowave.sh ${S3_URI}/
	@aws s3 cp scripts/emr/geowave-install-lib.sh ${S3_URI}/
	@aws s3 cp ${SERVER_ASSEMBLY} ${S3_URI}/
	@aws s3 cp ${INGEST_ASSEMBLY} ${S3_URI}/

create-cluster:
	aws emr create-cluster --name "${NAME}" ${COLOR_TAG} \
--release-label emr-4.5.0 \
--output text \
--use-default-roles \
--configurations "file://$(CURDIR)/scripts/configurations.json" \
--log-uri ${S3_URI}/logs \
--ec2-attributes KeyName=${EC2_KEY},SubnetId=${SUBNET_ID} \
--applications Name=Ganglia Name=Hadoop Name=Hue Name=Spark Name=Zeppelin-Sandbox \
--instance-groups \
Name=Master,${MASTER_BID_PRICE}InstanceCount=1,InstanceGroupType=MASTER,InstanceType=${MASTER_INSTANCE} \
Name=Workers,${WORKER_BID_PRICE}InstanceCount=${WORKER_COUNT},InstanceGroupType=CORE,InstanceType=${WORKER_INSTANCE} \
--bootstrap-actions \
Name=BootstrapGeoWave,Path=${S3_URI}/bootstrap-geowave.sh \
Name=BootstrapDemo,Path=${S3_URI}/bootstrap-demo.sh,\
Args=[--tsj=${S3_URI}/server-assembly-0.1.0.jar,--site=${S3_URI}/site.tgz] \
| tee cluster-id.txt

start-ingest: LIMIT=9999
start-ingest:
	@if [ -z $$START_DATE ]; then echo "START_DATE is not set" && exit 1; fi
	@if [ -z $$END_DATE ]; then echo "END_DATE is not set" && exit 1; fi

	aws emr add-steps --output text --cluster-id ${CLUSTER_ID} \
--steps Type=CUSTOM_JAR,Name="Ingest ${LAYER_NAME}",Jar=command-runner.jar,Args=[\
spark-submit,--master,yarn-cluster,\
--class,demo.LandsatIngestMain,\
--driver-memory,${MASTER_MEMORY},\
--executor-memory,${EXECUTOR_MEMORY},\
--executor-cores,${EXECUTOR_CORES},\
--conf,spark.dynamicAllocation.enabled=true,\
--conf,spark.yarn.executor.memoryOverhead=${YARN_OVERHEAD},\
--conf,spark.yarn.driver.memoryOverhead=${YARN_OVERHEAD},\
${S3_URI}/ingest-assembly-0.1.0.jar,\
--layerName,"${LAYER_NAME}",\
--bbox,\"${BBOX}\",\
--startDate,${START_DATE},\
--endDate,${END_DATE},\
--maxCloudCoverage,${MAX_CLOUD_COVERAGE},\
--limit,${LIMIT},\
--output,accumulo,\
--params,\"instance=accumulo,table=tiles,user=root,password=secret\"\
] | cut -f2 | tee last-step-id.txt

wait: INTERVAL:=60
wait: STEP_ID=$(shell cat last-step-id.txt)
wait:
	@while (true); do \
	OUT=$$(aws emr describe-step --cluster-id ${CLUSTER_ID} --step-id ${STEP_ID}); \
	[[ $$OUT =~ (\"State\": \"([A-Z]+)\") ]]; \
	echo $${BASH_REMATCH[2]}; \
	case $${BASH_REMATCH[2]} in \
			PENDING | RUNNING) sleep ${INTERVAL};; \
			COMPLETED) exit 0;; \
			*) exit 1;; \
	esac; \
	done

terminate-cluster:
	aws emr terminate-clusters --cluster-ids ${CLUSTER_ID}
	rm -f cluster-id.txt
	rm -f last-step-id.txt

clean:
	./sbt clean -no-colors
	rm -rf viewer/site.tgz
	rm -rf viewer/dist/*

proxy:
	aws emr socks --cluster-id ${CLUSTER_ID} --key-pair-file "${HOME}/${EC2_KEY}.pem"

ssh:
	aws emr ssh --cluster-id ${CLUSTER_ID} --key-pair-file "${HOME}/${EC2_KEY}.pem"

local-ingest: ${INGEST_ASSEMBLY}
	spark-submit --name "${NAME} Ingest" --master "local[4]" --driver-memory 4G \
${INGEST_ASSEMBLY} \
--credentials "file:///${PWD}/conf/credentials.json" \
--datasets "file://${PWD}/conf/datasets.json"

local-tile-server: CATALOG=catalog
local-tile-server:
	spark-submit --name "${NAME} Service" --master "local" --driver-memory 1G \
${SERVER_ASSEMBLY} local ${CATALOG}

define UPSERT_BODY
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${1}",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{
        "Value": "${2}"
      }]
    }
  }]
}
endef

update-route53: HOSTED_ZONE=ZIM2DOAEE0E8U
update-route53: RECORD=geotrellis-ndvi.geotrellis.io
update-route53: VALUE=$(shell aws emr describe-cluster --output text --cluster-id $(CLUSTER_ID) | egrep "^CLUSTER" | cut -f5)
update-route53: export UPSERT=$(call UPSERT_BODY,${RECORD},${VALUE})
update-route53:
	@tee scripts/upsert.json <<< "$$UPSERT"
	aws route53 change-resource-record-sets \
--hosted-zone-id ${HOSTED_ZONE} \
--change-batch "file://$(CURDIR)/scripts/upsert.json"

.PHONY: local-ingest local-tile-server update-route53
