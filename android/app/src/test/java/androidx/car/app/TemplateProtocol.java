package androidx.car.app;

import androidx.car.app.model.TemplateWrapper;

/** Exercise the same wrapper/stack path as AppManager's host Binder. */
public final class TemplateProtocol {
    public static TemplateWrapper getTemplate(CarContext context) {
        return context.getCarService(ScreenManager.class).getTopTemplate();
    }
}
