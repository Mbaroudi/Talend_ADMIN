// ============================================================================
// Talend_ADMIN — open-source CI builder application for Talend Open Studio.
//
// Talend never open-sourced its CommandLine/CI Builder plugin, but everything
// it calls IS open source and ships in the TOS distribution: the local
// repository, the code generator and BuildJobManager. This ~200-line Eclipse
// application is the missing headless driver:
//
//   logon local project -> locate the job -> generate code + build -> zip
//
// It is compiled at first start against the Studio's own plugins (see
// prepare-studio.sh) and launched through the equinox launcher with a plain
// JVM — no GUI, no GTK/X11.
//
// Licensed under the MIT License (this file); links against Apache-2.0
// licensed Talend Open Studio plugins at runtime.
// ============================================================================
package org.talendadmin.cibuilder;

import java.io.File;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.eclipse.core.resources.IProject;
import org.eclipse.core.resources.IProjectDescription;
import org.eclipse.core.resources.IWorkspace;
import org.eclipse.core.resources.ResourcesPlugin;
import org.eclipse.core.runtime.NullProgressMonitor;
import org.eclipse.core.runtime.Platform;
import org.eclipse.equinox.app.IApplication;
import org.eclipse.equinox.app.IApplicationContext;
import org.talend.commons.CommonsPlugin;
import org.talend.core.context.Context;
import org.talend.core.context.RepositoryContext;
import org.talend.core.model.general.ConnectionBean;
import org.talend.core.model.general.Project;
import org.talend.core.model.properties.ProcessItem;
import org.talend.core.model.properties.PropertiesFactory;
import org.talend.core.model.properties.User;
import org.talend.core.model.repository.ERepositoryObjectType;
import org.talend.core.model.repository.IRepositoryViewObject;
import org.talend.core.repository.model.ProxyRepositoryFactory;
import org.talend.core.repository.model.RepositoryFactoryProvider;
import org.talend.core.runtime.CoreRuntimePlugin;
import org.talend.repository.ui.wizards.exportjob.JavaJobScriptsExportWSWizardPage.JobExportType;
import org.talend.repository.ui.wizards.exportjob.scriptsmanager.BuildJobManager;
import org.talend.repository.ui.wizards.exportjob.scriptsmanager.JobScriptsManager.ExportChoice;
import org.talend.repository.ui.wizards.exportjob.scriptsmanager.JobScriptsManagerFactory;

public class CIBuilderApplication implements IApplication {

    @Override
    public Object start(IApplicationContext appContext) throws Exception {
        Map<String, String> args = parseArgs(Platform.getApplicationArgs());
        String projectName = require(args, "project");
        String jobName = require(args, "job");
        String destination = require(args, "destination");
        String contextName = args.getOrDefault("context", "Default");
        String version = args.getOrDefault("version", org.talend.core.model.relationship.RelationshipItemBuilder.LATEST_VERSION);

        CommonsPlugin.setHeadless(true);
        log("project=" + projectName + " job=" + jobName + " context=" + contextName
                + " version=" + version + " destination=" + destination);

        ProxyRepositoryFactory factory = ProxyRepositoryFactory.getInstance();
        try {
            // ---- repository context (local workspace provider) -------------
            ConnectionBean bean = ConnectionBean.getDefaultConnectionBean();
            User user = PropertiesFactory.eINSTANCE.createUser();
            user.setLogin("ci@talend-admin.local");

            Context ctx = CoreRuntimePlugin.getInstance().getContext();
            RepositoryContext repositoryContext = new RepositoryContext();
            ctx.putProperty(Context.REPOSITORY_CONTEXT_KEY, repositoryContext);
            repositoryContext.setUser(user);
            repositoryContext.setClearPassword("");
            repositoryContext.setFields(bean.getDynamicFields());

            factory.setRepositoryFactoryFromProvider(
                    RepositoryFactoryProvider.getRepositoriyById(bean.getRepositoryId()));

            // The local provider only reads Eclipse projects carrying the
            // Talend nature — register every project folder found in the
            // workspace directory (a bare git checkout has no .metadata).
            importWorkspaceProjects();

            Project project = null;
            for (Project p : factory.readProject()) {
                if (p.getLabel().equals(projectName) || p.getTechnicalLabel().equals(projectName)) {
                    project = p;
                    break;
                }
            }
            if (project == null) {
                throw new IllegalArgumentException("project '" + projectName + "' not found in workspace");
            }
            repositoryContext.setProject(project);

            log("logging on project " + project.getTechnicalLabel() + " ...");
            factory.logOnProject(project, new NullProgressMonitor());

            // ---- code generator templates (JET emitters) --------------------
            // The Studio initializes these in its "Generating code templates"
            // startup job; headless we must do it explicitly. Slow on the very
            // first run, cached at Studio level afterwards.
            log("initializing code generator templates (slow on first run) ...");
            org.eclipse.core.runtime.jobs.Job initJob =
                    ((org.talend.designer.codegen.ICodeGeneratorService) org.talend.core.GlobalServiceRegister
                            .getDefault().getService(org.talend.designer.codegen.ICodeGeneratorService.class))
                            .initializeTemplates();
            initJob.join();
            if (initJob.getResult() != null && !initJob.getResult().isOK()) {
                throw new IllegalStateException("code generator template initialization failed: "
                        + initJob.getResult());
            }

            // ---- locate the job ---------------------------------------------
            ProcessItem item = findProcessItem(factory, project, jobName);
            if (item == null) {
                throw new IllegalArgumentException("job '" + jobName + "' not found in project '"
                        + project.getTechnicalLabel() + "'");
            }
            String buildVersion = org.talend.core.model.relationship.RelationshipItemBuilder.LATEST_VERSION
                    .equals(version) ? item.getProperty().getVersion() : version;

            // ---- code generation + build + package --------------------------
            Map<ExportChoice, Object> choices = JobScriptsManagerFactory.getDefaultExportChoiceMap();
            choices.put(ExportChoice.binaries, true);
            choices.put(ExportChoice.needAssembly, true);
            choices.put(ExportChoice.contextName, contextName);

            log("building " + jobName + " " + buildVersion + " (POJO, binaries) ...");
            BuildJobManager.getInstance().buildJob(destination, item, buildVersion, contextName, choices,
                    JobExportType.POJO, new NullProgressMonitor());

            log("CI-BUILD SUCCESS: " + destination);
            return IApplication.EXIT_OK;
        } catch (Exception e) {
            System.err.println("[cibuilder] CI-BUILD FAILED: " + e);
            e.printStackTrace();
            // Non-zero exit code for the calling script.
            System.exit(2);
            return IApplication.EXIT_OK; // unreachable
        } finally {
            try {
                factory.logOffProject();
            } catch (Exception ignore) {
                // logoff failures must not mask the build result
            }
        }
    }

    private void importWorkspaceProjects() throws Exception {
        IWorkspace workspace = ResourcesPlugin.getWorkspace();
        File root = workspace.getRoot().getLocation().toFile();
        File[] children = root.listFiles(File::isDirectory);
        if (children == null) {
            return;
        }
        for (File dir : children) {
            if (!new File(dir, "talend.project").exists()) {
                continue;
            }
            IProject p = workspace.getRoot().getProject(dir.getName());
            if (!p.exists()) {
                log("importing workspace project folder: " + dir.getName());
                IProjectDescription desc = workspace.newProjectDescription(dir.getName());
                desc.setNatureIds(new String[] { org.talend.core.model.general.TalendNature.ID });
                p.create(desc, new NullProgressMonitor());
            }
            if (!p.isOpen()) {
                p.open(new NullProgressMonitor());
            }
        }
    }

    private ProcessItem findProcessItem(ProxyRepositoryFactory factory, Project project, String jobName)
            throws Exception {
        List<IRepositoryViewObject> all = factory.getAll(project, ERepositoryObjectType.PROCESS, true, false);
        IRepositoryViewObject best = null;
        for (IRepositoryViewObject o : all) {
            if (o.getLabel() != null && o.getLabel().equalsIgnoreCase(jobName)) {
                if (best == null || o.getVersion().compareTo(best.getVersion()) > 0) {
                    best = o;
                }
            }
        }
        return best == null ? null : (ProcessItem) best.getProperty().getItem();
    }

    private static Map<String, String> parseArgs(String[] argv) {
        Map<String, String> map = new HashMap<>();
        for (int i = 0; i < argv.length - 1; i++) {
            if (argv[i].startsWith("-") && !argv[i + 1].startsWith("-")) {
                map.put(argv[i].substring(1), argv[i + 1]);
                i++;
            }
        }
        return map;
    }

    private static String require(Map<String, String> args, String key) {
        String v = args.get(key);
        if (v == null || v.isEmpty()) {
            throw new IllegalArgumentException("missing required argument: -" + key);
        }
        return v;
    }

    private static void log(String msg) {
        System.out.println("[cibuilder] " + msg);
    }

    @Override
    public void stop() {
        // nothing to do: single-shot batch application
    }
}
