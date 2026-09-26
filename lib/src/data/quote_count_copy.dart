// How many quotes, in the form the number calls for.
//
// Found on 26 Sep 2026 while auditing what the commune fix left. The monthly
// allowance was written out by hand in three screens, and every one of them
// used a fixed noun for a count the server chooses:
//
//     'حتى $quoteLimit عروض في الشهر'                  // plan.dart, never called
//     'أرسلت ${quotesUsedThisMonth} هذا الشهر'        // subscription_screen
//     'استعملت $used من $limit عروض مجانية هذا الشهر' // subscription_screen
//     'بقي $left من $quoteLimit عروض هذا الشهر'        // worker_home_screen
//
// `quote_limit` is server-driven, so this is not a cosmetic risk sitting behind
// a hypothetical: a D1 UPDATE is the whole distance between the app being
// right here and wrong, with no release. Production ships 3 (free) and -1
// (every paid plan), and 3 happens to be in the broken-plural range, so the
// free plan reads correctly and the defect hides.
//
// **The paid branch was not hiding, though, and this tick found that out.** The
// backlog called it "nothing visibly wrong today", which is true of the *limit*
// and false of the *usage* count: for an unlimited plan the screen printed
// `'أرسلت ${used} هذا الشهر'` — a bare number with no noun at all. Every
// paying contractor is on that branch (`basic`, `pro` and `gold` all ship
// `quote_limit: -1`), so a man who sent 1 offer this month read «أرسلت 1 هذا
// الشهر» on his own revenue screen, and one who sent 5 read «أرسلت 5 هذا
// الشهر». Not a near-miss on a value the app has never seen: a missing noun on
// the only count every subscriber sees, live now.
//
// The agreement itself is not re-implemented here: it is [arabicCounted], the
// one the notification clock, the chat outbox, the commune picker and a
// contractor's own stats already share. This file owns the nouns and the cases
// that are not plain counts.
library;

import '../core/l10n/arabic_agreement.dart';

/// «عرض واحد» / «عرضان» / «3 عروض» / «11 عرض».
///
/// **One branches before the rule, and the bare singular goes in after it** —
/// the same trap the commune fix documents. Passing «عرض واحد» in as the
/// singular would be right for 1 and wrong for everything from 11 up, which
/// reuses that slot: «11 عرض واحد».
///
/// The 11+ form is the bare singular, not «عرضاً», and that is deliberate
/// rather than lazy. Every sentence in this file that prints a quote count puts
/// it either as the subject of a verb («أرسلت …») or straight after «من», and
/// the bare singular is the form that is correct in **both** of those slots.
/// «عرضاً» is accusative: correct after «من» in careful writing, wrong as a
/// subject, and wrong in half the sentences here. One form that is never
/// wrong beats two that are each wrong once.
String quotesAr(int n) {
  if (n <= 0) return '';
  if (n == 1) return 'عرض واحد';
  return arabicCounted(n, 'عرض', two: 'عرضان', few: 'عروض');
}

/// The usage line on the subscription card, under an unlimited plan.
///
/// This is the sentence that was missing its noun. The limit is not printed
/// here at all: there is no limit to print, and a number standing where a count
/// should be is what this file exists to stop.
///
/// **A brand-new subscriber gets the short form.** `quotesAr(0)` is silence by
/// design, so dropping it in unconditionally left the line reading
/// «عروض أسعار غير محدودة — أرسلت  هذا الشهر» with a hole where the count
/// was. The whole clause goes instead: he has sent nothing, and the sentence
/// that says so is the one about the limit, not a strained one about a zero.
String unlimitedQuotesUsageAr(int used) {
  final sent = quotesAr(used);
  if (sent.isEmpty) return 'عروض أسعار غير محدودة';
  return 'عروض أسعار غير محدودة — أرسلت $sent هذا الشهر';
}

/// «استعملت عرض واحد من 3 عروض مجانية هذا الشهر».
///
/// [isFree] adds «مجانية» and nothing else. The old code carried **two**
/// different fixed nouns for this one construction — «عروض» on the free branch
/// and «عرضاً» on the paid one — which is the same copy bug twice, in the same
/// widget, one line apart. Both counts now come from [quotesAr] and the
/// trailing noun is whichever form the limit itself takes, so the number after
/// «من» and the word that follows it can no longer disagree.
String cappedQuotesUsageAr(int used, int limit, {required bool isFree}) {
  final of = '${quotesAr(used)} من ${quotesAr(limit)}';
  return 'استعملت $of${isFree ? ' مجانية' : ''} هذا الشهر';
}

/// The plan row on the worker's home: «بقي عرضان من 3 عروض هذا الشهر».
///
/// Two counts, both from [quotesAr], and neither spelled by hand.
String quotesLeftLineAr(String nameAr, int left, int limit) =>
    '$nameAr — بقي ${quotesAr(left)} من ${quotesAr(limit)} هذا الشهر';
