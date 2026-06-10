# DEMO project — end-to-end HelloWorld

A minimal, real Talend project (raw Studio sources): project `DEMO`, one job
**`HelloWorld`** containing a single **tJava** that prints the `greeting`
context parameter. Two contexts are defined: `Default` and `Production`.

This is the project used to validate the full Talend_ADMIN chain:

```
git push ──► webhook handler ──► Rundeck "Build and Deploy Talend Job"
                                   ├─ tos-builder: .item → code gen → build
                                   └─ talend-runner: run over SSH
```

## Try it

```bash
# 1. publish this folder as a git repository named "HelloWorld"
#    (the webhook convention: repository name == job name)
cd examples/talend-project/demo
git init -b main . && git add -A && git commit -m "feat: HelloWorld job"
git remote add origin <your-git-url> && git push -u origin main

# 2. point a webhook at Talend_ADMIN (see README § CI/CD from Git),
#    or trigger manually in Rundeck:
#    Build and Deploy Talend Job → GIT_URL=<your-git-url>,
#    JOB_NAME=HelloWorld, BUILDER=tos
```

Expected execution output:

```
==============================================
Hello from Talend_ADMIN!
Job HelloWorld executed successfully via Talend_ADMIN
==============================================
```

Run it with `CONTEXT=Production` to get the Production greeting, or override
at run time with `CONTEXT_PARAMS=greeting=Your message here`.
