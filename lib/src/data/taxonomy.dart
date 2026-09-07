/// Static taxonomy shared with the web app — offline-cached so the core
/// screens work without a connection. Mirrors `/root/finili/app/lib/constants.ts`.
class Taxonomy {
  Taxonomy._();

  /// All 58 Algerian wilayas.
  static const List<({String id, String name})> wilayas = [
    (id: '01', name: 'أدرار'),
    (id: '02', name: 'الشلف'),
    (id: '03', name: 'الأغواط'),
    (id: '04', name: 'أم البواقي'),
    (id: '05', name: 'باتنة'),
    (id: '06', name: 'بجاية'),
    (id: '07', name: 'بسكرة'),
    (id: '08', name: 'بشار'),
    (id: '09', name: 'البليدة'),
    (id: '10', name: 'البويرة'),
    (id: '11', name: 'تمنراست'),
    (id: '12', name: 'تبسة'),
    (id: '13', name: 'تلمسان'),
    (id: '14', name: 'تيارت'),
    (id: '15', name: 'تيزي وزو'),
    (id: '16', name: 'الجزائر'),
    (id: '17', name: 'الجلفة'),
    (id: '18', name: 'جيجل'),
    (id: '19', name: 'سطيف'),
    (id: '20', name: 'سعيدة'),
    (id: '21', name: 'سكيكدة'),
    (id: '22', name: 'سيدي بلعباس'),
    (id: '23', name: 'عنابة'),
    (id: '24', name: 'قالمة'),
    (id: '25', name: 'قسنطينة'),
    (id: '26', name: 'المدية'),
    (id: '27', name: 'مستغانم'),
    (id: '28', name: 'المسيلة'),
    (id: '29', name: 'معسكر'),
    (id: '30', name: 'ورقلة'),
    (id: '31', name: 'وهران'),
    (id: '32', name: 'البيض'),
    (id: '33', name: 'إليزي'),
    (id: '34', name: 'برج بوعريريج'),
    (id: '35', name: 'بومرداس'),
    (id: '36', name: 'الطارف'),
    (id: '37', name: 'تندوف'),
    (id: '38', name: 'تيسمسيلت'),
    (id: '39', name: 'الوادي'),
    (id: '40', name: 'خنشلة'),
    (id: '41', name: 'سوق أهراس'),
    (id: '42', name: 'تيبازة'),
    (id: '43', name: 'ميلة'),
    (id: '44', name: 'عين الدفلى'),
    (id: '45', name: 'النعامة'),
    (id: '46', name: 'عين تيموشنت'),
    (id: '47', name: 'غرداية'),
    (id: '48', name: 'غليزان'),
    (id: '49', name: 'تيميمون'),
    (id: '50', name: 'برج باجي مختار'),
    (id: '51', name: 'أولاد جلال'),
    (id: '52', name: 'بني عباس'),
    (id: '53', name: 'عين صالح'),
    (id: '54', name: 'عين قزام'),
    (id: '55', name: 'تقرت'),
    (id: '56', name: 'جانت'),
    (id: '57', name: 'المغير'),
    (id: '58', name: 'المنيعة'),
  ];

  /// Service categories — the professional taxonomy of the marketplace.
  static const List<({String slug, String name, String icon})> categories = [
    (slug: 'construction', name: 'بناء عام وهيكل', icon: '🏗️'),
    (slug: 'renovation', name: 'ترميم وتجديد', icon: '🔨'),
    (slug: 'general_finishing', name: 'تشطيب عام وتسليم مفتاح', icon: '🔑'),
    (slug: 'painting', name: 'دهان وطلاء ديكوري', icon: '🎨'),
    (slug: 'plaster_drywall', name: 'جبس بورد وديكور', icon: '🏛️'),
    (slug: 'plumbing', name: 'سباكة وترصيص صحي', icon: '🚿'),
    (slug: 'electrical', name: 'كهرباء وإنارة', icon: '⚡'),
    (slug: 'tiling_marble', name: 'بلاط وسيراميك ورخام', icon: '🔲'),
    (slug: 'carpentry_aluminum', name: 'نجارة خشب وألمنيوم', icon: '🪟'),
    (slug: 'ironwork_welding', name: 'حدادة وتلحيم', icon: '🛡️'),
    (slug: 'waterproofing_insulation', name: 'عزل مائي وحراري', icon: '💧'),
    (slug: 'hvac_heating', name: 'تكييف وتدفئة', icon: '❄️'),
    (slug: 'epoxy_flooring', name: 'إيبوكسي وأرضيات', icon: '💎'),
    (slug: 'landscaping_exterior', name: 'تهيئة خارجية وحدائق', icon: '🌳'),
    (slug: 'venetian_plaster', name: 'جبس فينيسي وستوكو', icon: '🏛️'),
    (slug: 'wallpaper', name: 'ورق جدران', icon: '📜'),
  ];

  static String categoryName(String slug) {
    for (final c in categories) {
      if (c.slug == slug) return c.name;
    }
    return slug;
  }

  static String categoryIcon(String slug) {
    for (final c in categories) {
      if (c.slug == slug) return c.icon;
    }
    return '🛠️';
  }

  static String wilayaName(String id) {
    for (final w in wilayas) {
      if (w.id == id) return w.name;
    }
    return 'الجزائر';
  }
}