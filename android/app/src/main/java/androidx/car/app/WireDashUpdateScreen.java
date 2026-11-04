package androidx.car.app;

import android.content.pm.ApplicationInfo;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.car.app.model.TemplateWrapper;

/**
 * Compatibility adapter for Car App Library 1.8.0-rc01. That library creates a
 * new template ID on every host request, including state-only updates. Reuse its
 * existing ID mechanism when the app guarantees identical navigation structure.
 *
 * Kept in the library package to call the package-private mechanism directly;
 * no reflection or Android hidden APIs. Changing the pinned library requires
 * running the template protocol/Back-navigation tests.
 */
public abstract class WireDashUpdateScreen extends Screen {
    @Nullable private String lastStructure;
    @Nullable private String lastId;

    protected WireDashUpdateScreen(@NonNull CarContext context) {
        super(context);
    }

    /** Null opts out. Include every control ID, order, label and action setting. */
    @Nullable
    protected String stateUpdateStructure() {
        return null;
    }

    @Override
    @NonNull
    TemplateWrapper getTemplateWrapper() {
        String structure = stateUpdateStructure();
        if (structure != null && structure.equals(lastStructure)) {
            setUseLastTemplateId(true);
        }
        TemplateWrapper wrapper = super.getTemplateWrapper();
        if ((getCarContext().getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.d("WireDashAuto", "protocol template=" + wrapper.getTemplate().getClass().getSimpleName()
                    + " id=" + wrapper.getId() + " reused=" + wrapper.getId().equals(lastId));
        }
        lastId = wrapper.getId();
        lastStructure = structure;
        return wrapper;
    }
}
