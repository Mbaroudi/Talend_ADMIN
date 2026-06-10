# Example Talend job repository layout

The Talend builder compiles a **Maven-based Talend job export**. A repository it
can build looks like this:

```
my-talend-job/
├── pom.xml                 # Maven build (Talend "Build Job → Maven" export)
├── src/                    # generated job sources
│   └── main/java/...
├── contexts/              # Talend context files (Default, Production, ...)
├── routines/              # shared routines
└── items/                 # *.item / *.properties (job definitions)
```

`mvn clean package` must produce, under `target/`, either:

- a `.zip` containing `<Job>/<Job>_run.sh`, `lib/` and the job jar, **or**
- a runnable `.jar`.

The builder copies that artifact to `/artifacts/<JOB_NAME>/`, which the Rundeck
`talend-runner` node then executes.

## Producing an export from Talend Studio

1. Right-click the job → **Build Job**.
2. Choose **Maven** packaging (or **Autonomous Job** to get the `_run.sh`).
3. Commit the generated project to Git.

In CI you can instead use the Talend CI/Maven plugin to generate the same
Maven project automatically.

> No real job sources are shipped here — this folder documents the expected
> shape only.
