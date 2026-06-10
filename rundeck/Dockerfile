# One-shot provisioning image for Rundeck: creates the Talend project, the
# runner node source, imports the job templates and applies the operator ACL.
FROM alpine:3.20

RUN apk add --no-cache bash curl jq

COPY bootstrap.sh /bootstrap.sh
COPY projects/talend/jobs /jobs
COPY acl /acl
RUN chmod +x /bootstrap.sh

ENTRYPOINT ["/bootstrap.sh"]
