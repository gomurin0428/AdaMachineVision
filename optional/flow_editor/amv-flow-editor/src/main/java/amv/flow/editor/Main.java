package amv.flow.editor;

import javafx.application.Application;

/** Starts the editor; not a JavaFX Application itself, so JavaFX can be on the class path. */
public final class Main {

    private Main() {
    }

    public static void main(String[] args) {
        if (args.length > 0 && args[0].equals("--check")) {
            // Without a window: whether the engine library loads and is the
            // version this editor needs (exit status 0), for a package's test.
            int status;
            try {
                status = amv.flow.nativeapi.Flow.abiMatches() && !amv.flow.nativeapi.Flow.kindsJson().isEmpty()
                        ? 0 : 1;
            } catch (Throwable t) {
                t.printStackTrace();
                status = 2;
            }
            System.exit(status);
        }
        Application.launch(EditorApp.class, args);
    }
}
