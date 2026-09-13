/// Central store of Arabic UI strings. All user-facing copy lives here so
/// we can localise to other dialects/regions without touching screens.
class S {
  S._();

  // General
  static const appName = 'الو مقاول';
  static const continueBtn = 'متابعة';
  static const save = 'حفظ';
  static const cancel = 'إلغاء';
  static const back = 'رجوع';
  static const search = 'بحث';
  static const retry = 'إعادة المحاولة';
  static const loading = 'جارٍ التحميل...';

  // Notifications
  static const notifications = 'الإشعارات';
  static const markAllRead = 'تعليم الكل كمقروء';
  static const newTag = 'جديد';
  static const noNotifications = 'لا توجد إشعارات بعد';
  static const noNotificationsHint =
      'ستظهر هنا عروض الأسعار والرسائل وتحديثات مشاريعك.';

  // Auth
  static const loginTitle = 'تسجيل الدخول';
  static const loginSubtitle = 'أهلاً بعودتك إلى الو مقاول';
  static const registerTitle = 'إنشاء حساب جديد';
  static const phone = 'رقم الهاتف';
  static const email = 'البريد الإلكتروني';
  static const fullName = 'الاسم الكامل';
  static const password = 'كلمة المرور';
  static const confirmPassword = 'تأكيد كلمة المرور';
  static const login = 'دخول';
  static const createAccount = 'إنشاء الحساب';
  static const haveAccount = 'لديك حساب؟';
  static const noAccount = 'ليس لديك حساب؟';
  static const workerLabel = 'أنا مقاول/حرفي';
  static const customerLabel = 'أنا صاحب مشروع';
  static const workerDesc =
      'اعرض خدماتك، استقبل طلبات المشاريع، وقدّم عروضك مع تقييمات موثوقة.';
  static const customerDesc =
      'انشر مشروعك، استقبل عروض المقاولين الموثوقين، وتابع العمل حتى التسليم.';
  static const phoneHint = 'مثال: 0550123456';
  // Phone entry (see widgets/phone_field.dart). The invalid message is the same
  // rule the API enforces, so a user who solves it here never meets the server's
  // version of it.
  static const phoneHintIntl = 'مثال: 550 12 34 56';
  static const phoneRequired = 'رقم الهاتف مطلوب';
  static const phoneInvalid = 'رقم غير صحيح: 10 أرقام تبدأ بـ 05 أو 06 أو 07';
  static const phoneSwitchToIntl = 'الكتابة بالصيغة الدولية +213';
  static const phoneSwitchToLocal = 'الكتابة بالصيغة المحلية 0X';
  static const rememberMe = 'تذكرني';

  // Permissions (Arabic rationale shown before requesting camera/gallery)
  static const cameraRationale =
      'نحتاج الكاميرا لالتقاط صور مشروعك أو إثبات هويتك. صورك تبقى خاصة بك.';
  static const galleryRationale =
      'نحتاج الوصول إلى صورك لإرفاقها بمشروعك أو بمعرض أعمالك.';
  static const notificationRationale =
      'نرسل لك إشعارات عند وصول عروض جديدة أو رسائل من المقاولين.';

  // Errors.
  //
  // One sentence per failure class, each naming the problem AND the next action,
  // each written with Arabic letters only — no Latin word, no HTTP status, no
  // raw exception text. `error_copy.dart` is the only code that renders these,
  // and `test/error_copy_test.dart` fails the build if any of them learns a
  // Latin letter or loses its instruction.
  static const errOffline =
      'تعذّر الاتصال بالخادم. تأكّد من اتصالك بالإنترنت ثم أعد المحاولة.';
  static const errCheckConnection =
      'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة.';
  static const errTimeout =
      'الخادم تأخّر في الرد. تحقّق من الشبكة ثم أعد المحاولة.';
  static const errServer =
      'خلل مؤقّت في الخادم. أعد المحاولة بعد لحظات، وإن تكرّر الأمر جرّب لاحقاً.';
  static const errUnauthorized = 'انتهت جلستك. سجّل الدخول من جديد للمتابعة.';
  static const errForbidden =
      'لا تملك صلاحية لهذا الإجراء. ارجع للخلف أو سجّل الدخول بحساب آخر.';
  static const errNotFound =
      'هذا العنصر لم يعد متوفراً. ارجع للخلف وحدّث القائمة ثم أعد المحاولة.';
  static const errValidation =
      'البيانات المُرسلة غير مقبولة. راجع الحقول المطلوبة ثم أعد المحاولة.';
  static const errConflict =
      'تغيّر هذا العنصر من مكان آخر. حدّث القائمة ثم أعد المحاولة.';
  static const errTooLarge =
      'الملف أكبر من الحد المسموح. اختر ملفاً أصغر ثم أعد المحاولة.';
  static const errTooMany =
      'طلبات كثيرة في وقت قصير. انتظر دقيقة ثم أعد المحاولة.';

  /// Shown when the notification list could not be fetched — the list is empty
  /// because the request failed, not because nothing happened, and the copy has
  /// to say which of the two it is.
  static const noNotificationsErrorHint =
      'تعذّر الاتصال بالخادم. تحقّق من الشبكة ثم أعد المحاولة.';

  static const errUnexpected =
      'حدث خطأ غير متوقع. أعد المحاولة، وإن تكرّر الأمر أغلق التطبيق وافتحه من جديد.';
  static const errNoServer =
      'التطبيق غير مضبوط على عنوان الخادم. حدّث التطبيق من المتجر ثم أعد المحاولة.';
  static const errUpload =
      'تعذّر رفع الملف. تأكّد من الإنترنت ثم أعد المحاولة.';
  static const errPickFailed =
      'لم نتمكّن من إتمام العملية على الصورة. أعد المحاولة، وإن تكرّر الأمر اختر صورة أخرى.';
  static const errPhotoPermission =
      'لم نتمكّن من الوصول إلى صورك. افتح إعدادات الهاتف وامنح إذن الصور ثم أعد المحاولة.';
  static const errCameraPermission =
      'لم نتمكّن من فتح الكاميرا. افتح إعدادات الهاتف وامنح إذن الكاميرا ثم أعد المحاولة.';
}
