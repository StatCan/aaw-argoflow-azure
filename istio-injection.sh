kubectl label namespace trino-system istio-injection=enabled
kubectl label namespace hive-system istio-injection=enabled
kubectl label namespace minio-system istio-injection=enabled

kubectl rollout restart deploy trino-coordinator -n trino-system
kubectl rollout restart deploy trino-worker -n trino-system
kubectl rollout restart deploy minio -n minio-system

kubectl delete pod hive-metastore-0 -n hive-system
kubectl delete pod hive-metastore-mariadb-0 -n hive-system