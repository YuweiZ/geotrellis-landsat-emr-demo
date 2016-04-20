EMR_TARGET=s3://geotrellis-test/emr
KEY_NAME=geotrellis-cluster

AWS_REGION="us-east-1"

MASTER_INSTANCE=m3.xlarge
MASTER_PRICE=0.15
DRIVER_MEMORY=10g

# 40 m3.2xlarges, using 5 cores each,
WORKER_INSTANCE=m3.2xlarge
WORKER_PRICE=0.15
WORKER_COUNT=3

# M3.2XLARGE
#    8 cores
#   30 GB
#  160 GB SSD

NUM_EXECUTORS=1 #400
EXECUTOR_MEMORY=10G
EXECUTOR_CORES=4
EXECUTOR_YARN_OVERHEAD=520
DRIVER_YARN_OVERHEAD=520
