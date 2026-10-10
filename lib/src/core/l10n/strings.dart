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

  /// Shown when a notification row carries nothing openable.
  static const notificationNoAction = 'لا يوجد إجراء لهذا الإشعار.';

  // Marking a notification read, when the server never answered.
  //
  // `POST /api/notifications/read` is **idempotent**, so unlike the thread-open
  // write these sentences may offer a retry — and the split between the two
  // unconfirmed cases is the contract: «missing» means the server answered and
  // refused, «unknown» means the phone cannot read the server at all. The
  // second must not say «re-try», because re-sending a write of unknown
  // outcome is the habit this app removed from the chat screen last cycle.
  /// The re-read proved the row is read: the write landed, nothing to do.
  static const notifReadUnconfirmedLanded = 'تم تعليم الإشعار كمقروء.';

  /// The server answered and the row is still unread. Safe to press again —
  /// the write changes nothing that is already true.
  static const notifReadUnconfirmedMissing =
      'لم نتمكن من تعليم الإشعار كمقروء. أعد المحاولة.';

  /// The re-read itself failed. Says plainly that this proves nothing, and
  /// sends the user to the list instead of a button that re-issues a write.
  static const notifReadUnconfirmedUnknown =
      'تعذّر التأكّد. تحقّق من قائمة الإشعارات عند عودة الاتصال.';

  /// Shown above the verdict, while the app re-reads the centre.
  static const notifReadUnconfirmedRecheck = 'نتحقّق من الإشعارات…';

  /// Read aloud by a screen reader on the header pip when the count is the
  /// phone's guess rather than the server's answer.
  ///
  /// **It is a label and not a sentence on purpose.** The user has already
  /// been told «تعذّر التأكّد» by the centre; repeating that here would put the
  /// same doubt in two places and teach people to ignore it. What the pip owes
  /// them is the *absence of a claim*, so it announces that the number is
  /// unconfirmed and stops — same words for the same state, no second verdict.
  static const notifCountUnconfirmed = 'غير مؤكّد';

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
  /// A write whose outcome the app refuses to guess: the request left the
  /// phone but no answer arrived inside the host timeout, and the network layer
  /// will not re-send it to the second host because both hosts answer from the
  /// same Worker (a re-send would post the project/quote/message twice).
  /// The project already carries as many photos as it may. A sentence and not a
  /// silent button: a tile that simply is not there reads as a broken screen,
  /// and the user has just been told nothing about a cap that does exist.
  static const errProjectPhotoCap =
      'وصلت للحد الأقصى من الصور لهذا المشروع (10 صور). احذف صورة لإضافة أخرى.';

  static const errWriteUnconfirmed =
      'انقطع الاتصال قبل تأكيد وصول طلبك. تحقّق من القائمة قبل إعادة المحاولة.';
  /// Spoken after the app re-reads the list because a write's outcome was
  /// unknown. It has to answer the one question the sentence above creates:
  /// «is my project on the list or not?». Telling the user to check is only
  /// honest when the list on screen is the fresh one, so the screen refetches
  /// and then says which of the two things is true.
  static const writeUnconfirmedRecheck = 'نتحقّق الآن من القائمة…';
  static const writeUnconfirmedLanded = 'وجدناه في القائمة — الطلب وصل بنجاح';
  static const writeUnconfirmedMissing =
      'لم نجده في القائمة — الطلب لم يصل، أعد المحاولة';

  /// The answer for an **edit** that could not be confirmed, when the re-read
  /// found every value the form was sending. Deliberately a different sentence
  /// from [writeUnconfirmedLanded] and not just a reuse of it: that one says
  /// «وجدناه في القائمة», which is a claim about *finding a row* — true on the
  /// create path, meaningless here, where the row was in the list the whole
  /// time and the question is whether it now carries these values.
  static const editUnconfirmedLanded = 'التعديلات محفوظة — التأكيد وصل بنجاح';
  /// The edit did not land, and [field] is what the project still carries.
  ///
  /// Naming the field is the whole point. «لم يُحفظ التعديل» sends a client who
  /// fixed a budget back into the form to compare every field by eye; «الميزانية
  /// لم تتغيّر» puts his finger on the box he has to look at. The noun is a
  /// field, the instruction is the same «أعد المحاولة» every other missing
  /// outcome carries, because the retry is real: nothing was stored, so a second
  /// save cannot duplicate anything.
  static const editUnconfirmedMissing = 'ما زال المشروع يحمل: %s — أعد المحاولة';
  /// The re-read failed too. Same refusal as [writeUnconfirmedUnknown] and for
  /// the same reason: nothing true can be said about a write the app cannot
  /// read back, and «لم يُحفظ» would be a guess in the one direction that
  /// costs the user his edit.
  /// An edit whose **fields** all reached the server while a photo did not
  /// answer, and %s is the counted photo word.
  ///
  /// Its own sentence rather than a qualifier on [editUnconfirmedLanded],
  /// because «التعديلات محفوظة» is a claim about *everything* the form sent.
  /// Attaching a caveat to a success sentence is how the caveat gets read as
  /// part of it, and the photo is the one thing here that genuinely may not
  /// exist on the server. The re-read can prove the row carries the new values
  /// and can say nothing at all about the blob, so the sentence says the second
  /// thing and stays quiet about the first.
  static const editUnconfirmedPhotoUnchecked =
      'حُفظت التعديلات، أما %s فلم يصلنا جوابها — تحقّق من صور المشروع';
  static const editUnconfirmedUnknown =
      'تعذّر الاتصال للتحقّق من التعديل — تحقّق من مشروعك قبل إعادة المحاولة';
  /// The field names [editUnconfirmedMissing] can interpolate, in the app's own
  /// Arabic and never as a raw enum value.
  static const fieldTitle = 'العنوان';
  static const fieldCategory = 'التخصص';
  static const fieldWilaya = 'الولاية';
  static const fieldCommune = 'البلدية';
  static const fieldBudget = 'الميزانية';
  static const fieldUrgency = 'الأولوية';
  static const fieldDescription = 'الوصف';
  static const fieldImages = 'الصور';

  // ---- Saving the contractor's own profile ------------------------------
  //
  // Three sentences for one write, and the reason they are not the write-
  // outcome trio is the point: those answer a write whose outcome was
  // *unknown*, and this one answered 200. The row on screen says otherwise.
  //
  // `profileSavedFieldHeld` is the honest shape — the server took the request
  // and kept a different value. It must not read as failure either: the
  // contractor is told exactly which field is not the one he saved, which is
  // the only thing that sends him back to the right box, and it ends on an
  // action («افتح ملفك») rather than on an apology.
  /// Every field the profile save touches came back as the server holds it.
  static const profileSavedOk = 'حُفظت ملفك بنجاح';
  /// The server took the request and did not keep what the form sent.
  /// Deliberately names the field and not «لم يُحفظ» — an unnamed failure on a
  /// form this long sends the user hunting through nine boxes.
  static const profileSavedFieldHeld =
      'لم يحفظ الحقل: %s. افتح ملفك للتأكد وراجعه ثم ذهب';
  /// The verification read itself failed. NOT a claim that the save failed: the
  /// PATCH answered 200, so this only says the app could not check.
  static const profileSavedUnverified =
      'حُفظ ملفك، لكننا لم نتكّن التأكد تمامًا — افتح ملفك للتأكد وراجعه';
  /// The field names [profileSavedFieldHeld] can interpolate, in the app's own
  /// Arabic and never as a raw key.
  static const fieldName = 'الاسم الظاهر';
  static const fieldSpecialties = 'التخصصات';
  static const fieldBio = 'النبذة';
  static const fieldExperience = 'سنوات الخبرة';
  static const fieldPriceRange = 'أسعارك';
  static const fieldRadius = 'نطاق الخدمة';
  static const fieldAvailability = 'توافر العمل';
  /// The device refused to store a message the user just typed, so it is on
  /// the screen and nowhere else. This is the one chat sentence that must never
  /// claim the opposite: «الرسالة محفوظة في الهاتف» is what a failed send says,
  /// and it is a lie here — closing the app, or letting Android kill it, takes
  /// the words with it. Hence the instruction is «copy it down», not «retry»:
  /// a retry is what the other sentence is for, and telling this user to press
  /// it would bury the one thing he can still do.
  static const chatNotSaved =
      'تعذّر حفظ الرسالة على الهاتف. انسخها قبل إغلاق التطبيق، ثم أعد المحاولة.';
  /// The «do not send this again» note the app writes after a write's answer is
  /// lost **did not reach the disk**, so the phone is still holding that message
  /// as «safe to re-send».
  ///
  /// The two paths that write that note share this sentence, and the two are
  /// not the same failure:
  ///
  ///  * a write that may already be stored, whose *mark* is missing, is one
  ///    restart away from being sent again by the app with no user action. The
  ///    server may already hold the words, so this is a duplicate, and the
  ///    user has no idea how to prevent it — there is no button for it.
  ///  * a re-read that could not be read at all cannot be retried from here
  ///    either, which is why this sentence does **not** say «check the list».
  ///    The list is exactly what the app could not read.
  ///
  /// So the one instruction is «copy the words down now», while they are still
  /// on a screen that has them. «أعد المحاولة» would be a lie in both cases:
  /// the send is precisely the thing that must not happen, and pressing the
  /// bubble would do it anyway.
  static const markUnconfirmedNotSaved =
      'تعذّر حفظ علامة «لا تُرسل مجدداً» على الهاتف. انسخ الرسالة الآن قبل إغلاق التطبيق.';
  /// The re-read came back and the message really is not on the server — so it
  /// is an ordinary failure and re-sending is correct — but the note that would
  /// have made the queue retryable after a restart did not reach the disk. The
  /// record on the phone still reads «unconfirmed», and a record in that state
  /// comes back with no retry affordance and is skipped by the startup flush.
  ///
  /// Both halves are in the sentence because the user acts on both: the retry
  /// line is real and the words are on the screen, but the window is *now*, and
  /// closing the app strands a message that is on neither the server nor the
  /// server's re-send list.
  static const markClearedNotSaved =
      'لم نجده في القائمة — الطلب لم يصل. أعد المحاولة الآن قبل إغلاق التطبيق.';
  /// The re-read failed too, so the app still does not know. Deliberately
  /// carries no action: any instruction here would be a guess about a write it
  /// cannot see. «حاول مجدداً» is the only safe one and it is in the next clause.
  static const writeUnconfirmedUnknown =
      'تعذّر الاتصال للتحقّق — تحقّق من القائمة قبل إعادة المحاولة';

  // ---- The three owner commits on the project detail screen -------------
  //
  // Six sentences for three writes, and they are six on purpose. The owner's
  // question is never «did my request arrive» but «did *that button* work»,
  // and he has three buttons whose consequences are not interchangeable: a
  // signed contract, a closed job, a withdrawn one. A single shared sentence
  // («وجدناه في القائمة») answers a question about a row that was on screen
  // the whole time, and leaves him to work out which of the three things
  // actually happened.
  //
  // Each pair is a *state*, not a request. «تم قبول العرض» is the app
  // asserting the contract exists; the unconfirmed variant says the same thing
  // on weaker evidence, and the difference between them is the whole reason
  // this file exists.
  static const acceptUnconfirmedLanded =
      'تم قبول العرض — المقاول مُعيَّن في المشروع';
  static const acceptUnconfirmedMissing =
      'لم يُعتمد القبول — المشروع ما زال مفتوحاً، أعد المحاولة';
  static const completeUnconfirmedLanded =
      'تم إغلاق المشروع — يمكنك تقييم المقاول الآن';
  static const completeUnconfirmedMissing =
      'لم يُغلق المشروع — ما زال قيد التنفيذ، أعد المحاولة';
  static const cancelUnconfirmedLanded = 'تم إلغاء المشروع — سُحبت عروضه';
  static const cancelUnconfirmedMissing =
      'لم يُلغَ المشروع — ما زال معروضاً، أعد المحاولة';
  /// The re-read came back and the row is committed to somebody **else**.
  ///
  /// Its own sentence, and deliberately not a degraded [writeUnconfirmedUnknown]
  /// and certainly not the «أعد المحاولة» that [WriteOutcome.missing] ends
  /// with: the accept did not land, but retrying is now impossible — the
  /// server has this project assigned, and every other quote on the screen now
  /// answers 409. A client who is told to retry will retry until he believes
  /// the app is broken. This one says what is true and sends him to the state
  /// he is in.
  static const commitUnconfirmedReassigned =
      'هذا المشروع معيَّن لمقاول آخر — القبول لم يُنفَّذ، راجع حالة المشروع';
  /// The project is cancelled, so the close the user tapped can no longer
  /// happen. Same reason as [commitUnconfirmedReassigned]: «أعد المحاولة» would
  /// promise a control that is no longer on the screen.
  static const commitUnconfirmedUncancellable =
      'المشروع مُلغى — لم يعد بالإمكان إغلاقه';
  /// The re-read itself failed on one of these three writes. Distinct from
  /// [writeUnconfirmedUnknown] only in that it drops «تحقّق من القائمة»: the
  /// project is already on screen, so there is no list to go and check — the
  /// useful instruction is to reopen this page, which is the only thing that
  /// re-reads it.
  static const commitUnconfirmedUnknown =
      'تعذّر الاتصال للتحقّق — افتح المشروع من جديد قبل إعادة المحاولة';
  /// The permanent line under a bubble the app could not confirm, as opposed to
  /// [writeUnconfirmedUnknown] which is the one-shot toast. Same rule, and for
  /// the same reason: there is no true action while the phone cannot read the
  /// thread, so this line names the state and stops. Drawing the red retry line
  /// here is what would let one message become two.
  // ---- The verification dossier -----------------------------------------
  //
  // Its own pair, and the same reason the three owner commits above have
  // theirs: the question is never «did my request arrive» but «did *that
  // button* work», and here the thing that moved is a document queue. The
  // shared [writeUnconfirmedLanded] would claim «وجدناه في القائمة» — a claim
  // about finding a row, when the profile was on screen the entire time and
  // the only question is whether its queue grew.
  static const dossierUnconfirmedLanded =
      'وصلت مستنداتك — حسابك الآن قيد المراجعة';
  /// The re-read came back with the profile **unchanged**, which is the one
  /// answer that proves nothing arrived: the server did not move.
  ///
  /// Carries «أعد المحاولة» because the retry is real — nothing was stored, so
  /// re-sending the same three documents cannot duplicate a row. The sentence
  /// names what happened to the *dossier* rather than the request, because a
  /// contractor who is told only «did not arrive» re-picks his ID card from
  /// the gallery twice, wondering which of the two went missing.
  static const dossierUnconfirmedMissing =
      'لم تصل مستنداتك — ما زالت كما هي، أعد الإرسال';
  static const chatUnconfirmed = 'لم يتأكّد وصولها — النتيجة غير معروفة';

  // ---- Opening a thread ---------------------------------------------------
  //
  // Its own three sentences, and the reason is the same one that gave the
  // dossier and the three owner commits their own: the user never asks «did my
  // request arrive», he asks «can I talk to this person».
  //
  // **None of the three says «أعد المحاولة»**, and that is the part that is
  // load-bearing. The screen that prints them has one button, and it re-runs
  // the `POST /api/mobile/conversations` that produced the failure. The route
  // is a get-or-create for a (customer, worker, project) triple, so a second
  // POST is *probably* harmless — but «probably» is doing real work in that
  // sentence, and it is a sentence this app would be printing to a user. The
  // inbox is a GET, it is always reachable, and it is where a thread that
  // really exists is listed. So every answer here points at the inbox instead,
  // and the app never tells anyone to press the button that may open a second
  // conversation.
  static const threadUnconfirmedLanded =
      'المحادثة مفتوحة — تجدها في قائمة الرسائل';
  /// The inbox answered and holds no such conversation, so the write did not
  /// land. Carries the inbox as the place to look *and* the fact that the
  /// thread is not there, so a user who opens the inbox and sees nothing
  /// knows the answer rather than suspecting a second bug.
  static const threadUnconfirmedMissing =
      'تعذّر فتح المحادثة — تحقّق من قائمة الرسائل';
  /// The re-read could not run, so the app still does not know whether a
  /// conversation exists.
  ///
  /// **Its own sentence, and this is the one the test caught.** It was first
  /// written as an alias of [writeUnconfirmedUnknown], on the reasoning that
  /// the re-read that failed *was* the inbox, so the shared line names the
  /// right list. That reasoning is right about the list and wrong about
  /// everything else: the shared line ends in «قبل إعادة المحاولة», and on
  /// this page «re-try» is the `POST`. So the one sentence that fires when the
  /// phone cannot read the server was also the one sentence instructing the
  /// user to re-issue the write — and it fired in precisely the case where the
  /// app has just proved the server is unreachable. The same screen, the same
  /// outcome, three different words for the list the user has to open.
  static const threadUnconfirmedUnknown =
      'تعذّر الاتصال للتحقّق — تحقّق من قائمة الرسائل';

  /// The two headings above [threadUnconfirmedLanded] / [threadUnconfirmedMissing].
  ///
  /// Split because the two states are not the same kind of thing to a user: one
  /// says the app sorted it out and the thread is waiting for him, the other
  /// says the app cannot tell and the inbox is the only place that can. One
  /// heading with two bodies would make a *failure* and a *success* sound the
  /// same at the top of the page, where the eye lands first.
  static const threadUnconfirmedTitleLanded = 'المحادثة جاهزة';
  /// Not a scare word. The app is not certain the thread failed — it is certain
  /// it cannot tell, and «غير واضح» is the accurate state. «تعذّر» would be a
  /// verdict on a write that may have landed, which is the claim this whole
  /// family of files exists not to make.
  static const threadUnconfirmedTitleUnclear = 'لم تتأكّد نتيجة الفتح';

  /// The action on that page, and the list the copy points at.
  static const openInbox = 'قائمة الرسائل';
  /// The banner's action when the only outstanding message is the unconfirmed
  /// one. «تحقّق» is honest because the thread re-reads on tap and either finds
  /// the row or says it is not there; «إرسال» would promise a re-send.
  static const chatUnconfirmedRecheck = 'تحقّق';
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

  /// A 402 carries the server's own Arabic sentence when it has one, and this
  /// is the fallback: it names the cause and points at the screen that fixes it.
  static const errPlanLimit =
      'خطتك الحالية لا تسمح بهذا الإجراء. افتح «اشتراكي» لترقية الاشتراك ثم أعد المحاولة.';

  // Subscription (اشتراك المقاول).
  static const planTitle = 'اشتراكي';
  static const planNoteFallback =
      'الاشتراك فقط: بدون عمولة على الطلبات وبدون أي نسبة من سعر المشروع.';
  static const planCurrent = 'خطتك الحالية';
  static const planChoose = 'اختر خطتك';
  static const planFree = 'مجاني';
  static const planPerMonth = 'شهرياً';
  static const planPerYear = 'سنوياً';
  static const planFreeSuffixMonthly = 'تدفع شهرياً';
  static const planFreeSuffixYearly = 'تدفع سنوياً';
  // REMOVED: `planYearlyHint` = «سنة كاملة بسعر عشرة أشهر».
  //
  // A hard-coded claim about a number the server owns, printed under the
  // yearly option on **every** plan. Every paid plan is priced at exactly
  // ten months today, so it read true; it was still a promise the client
  // invented. The sentence is now `yearlyTermHintAr(plan)` in
  // `data/plan_renewal_copy.dart`, computed per plan and printed on the card
  // beside the price. Deleted rather than left in `S` so a later screen
  // cannot reach for the constant and reintroduce the claim.
  static const planUpgrade = 'ترقية الاشتراك';
  static const planRenew = 'تجديد الاشتراك';
  // The label on a plan card whose payment request is already filed. Not
  // «ترقية» and not a greyed-out upgrade: the card is the same product at the
  // same price, and what is missing is a *second* transfer for a request that
  // is already with support. The sentence under it names the request number.
  static const planRequestedAwaiting = 'بانتظار تأكيد الدفع';
  static const planPendingTitle = 'طلبك قيد المراجعة';
  static const planPendingBody =
      'استلمنا طلبك. يُفعَّل الاشتراك بعد تأكيد الدفع، وسيصلك إشعار عند التفعيل.';
  static const planPayTitle = 'طريقة الدفع';
  static const planReferenceLabel = 'رقم العملية في الإشعار (اختياري)';
  static const planCodeTitle = 'عندك رمز تفعيل؟';
  static const planCodeHint = 'أدخل الرمز هنا';
  static const planActivate = 'تفعيل';
  /// Claimed **only** when the server's answer actually carried the plan that
  /// is now live. It used to be printed whenever the answer carried nothing, so
  /// an empty or half-shaped response read as «تم تفعيل اشتراكك» — a money
  /// claim with no evidence behind it, on the one screen where a contractor has
  /// just handed over 30000 دج. See `redeem_outcome.dart`.
  static const planCodeOk = 'تم تفعيل اشتراكك';
  /// The redemption's answer named no plan, so the app cannot claim it worked
  /// and cannot claim it failed either. Deliberately its own sentence rather
  /// than [planCodeOk] and rather than a bare [S.writeUnconfirmedUnknown]:
  /// «الرمز لم يُفعِّل شيئاً» would read as a verdict on the code, and a
  /// single-use code the server already burned is exactly what a man is told to
  /// buy again on the strength of one missing field.
  static const planCodeNoPlan =
      'لم يُرجع الخادم تفاصيل التفعيل — تحقّق من اشتراكك قبل إعادة إدخال الرمز';
  static const planRequestOk = 'أرسلنا طلبك، ويُفعَّل بعد تأكيد الدفع';
  static const planSupportFallback =
      'لا توجد تفاصيل دفع منشورة بعد. تواصل معنا لتفعيل اشتراكك يدوياً.';
  static const planLoadFailed = 'تعذّر تحميل خطط الاشتراك';
  static const planQuotaTitle = 'انتهت حصة هذا الشهر';
  static const planQuotaBody =
      'وصلت إلى الحد المجاني في العروض. رقّي اشتراكك لتُرسل عروضاً بلا حد.';
  static const planRetry = 'إعادة المحاولة';

  // ---- The bid sheet's own validation (see _BidSheetState in
  // screens/project/project_detail_screen.dart) ----------------------------
  // Three sentences that used to be printed on the *project page*, by a
  // snackbar, after the sheet had already closed and disposed the three
  // controllers holding what he typed. `bidAmountMin` is the same rule the API
  // enforces, and it is now drawn **under the field that is wrong** rather
  // than on a screen above one he is no longer looking at.
  //
  // Empty is an error and not silence, unlike the project budget row
  // (`project_new_screen._budgetError`, where the budget is genuinely
  // optional): `submitQuote` requires an amount, so an empty field is a bid
  // that cannot be sent, not a bid that needs no saying.
  static const bidAmountRequired = 'المبلغ مطلوب';
  static const bidAmountMin = 'المبلغ يجب أن يكون 1000 دج على الأقل';
  static const bidAmountNotNumber = 'المبلغ يجب أن يكون رقماً بالدينار';
  static const bidDaysNotNumber = 'مدة الإنجاز يجب أن تكون عدداً من الأيام';

  // ---- The other end of a bound: a value that is a number and still cannot be
  // sent. Floors said "at least", so they read as rules; roofs have to say
  // what is too much, or a contractor who types 13 digits is told the field
  // "is not a number" for a field holding nothing but digits — which is a lie
  // about the value and teaches him the app does not know its own limits.
  //
  // Functions, not constants, because both numbers come from [DzNumber]: a
  // copied literal here would be a second place to move when the roof moves,
  // and this file already holds the Arabic half of the bid sheet's rules.
  static String bidAmountMax(int max) =>
      'المبلغ يجب ألا يتجاوز $max دج';
  static String bidDaysMax(int max) =>
      'مدة الإنجاز يجب ألا تتجاوز $max يوماً';
}
