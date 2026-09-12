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
  static const rememberMe = 'تذكرني';

  // Permissions (Arabic rationale shown before requesting camera/gallery)
  static const cameraRationale =
      'نحتاج الكاميرا لالتقاط صور مشروعك أو إثبات هويتك. صورك تبقى خاصة بك.';
  static const galleryRationale =
      'نحتاج الوصول إلى صورك لإرفاقها بمشروعك أو بمعرض أعمالك.';
  static const notificationRationale =
      'نرسل لك إشعارات عند وصول عروض جديدة أو رسائل من المقاولين.';
}