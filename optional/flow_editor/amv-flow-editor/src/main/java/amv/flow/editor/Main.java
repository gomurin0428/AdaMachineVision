package amv.flow.editor;

import javafx.application.Application;

/** Starts the editor; not a JavaFX Application itself, so JavaFX can be on the class path. */
public final class Main {

    private Main() {
    }

    public static void main(String[] args) {
        Application.launch(EditorApp.class, args);
    }
}
