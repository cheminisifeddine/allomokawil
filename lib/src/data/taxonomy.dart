import 'package:flutter/material.dart';

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
  ///
  /// `icon` is a bundled Material icon, deliberately NOT an emoji: emoji render
  /// as tofu boxes on many older Android builds (that is why one tile in the
  /// old UI showed an empty rectangle), and the old set even reused 🏛️ twice.
  /// `tint`/`wash` are explicit colours so a tile can never inherit a bad one.
  static const List<
      ({String slug, String name, IconData icon, Color tint, Color wash})>
      categories = [
    (
      slug: 'construction',
      name: 'بناء عام وهيكل',
      icon: Icons.engineering_rounded,
      tint: Color(0xFF2C5FA8),
      wash: Color(0xFFEAF1FB)
    ),
    (
      slug: 'renovation',
      name: 'ترميم وتجديد',
      icon: Icons.handyman_rounded,
      tint: Color(0xFFC9821B),
      wash: Color(0xFFFDF3E3)
    ),
    (
      slug: 'general_finishing',
      name: 'تشطيب عام وتسليم مفتاح',
      icon: Icons.key_rounded,
      tint: Color(0xFF1E8E5A),
      wash: Color(0xFFE7F5EE)
    ),
    (
      slug: 'painting',
      name: 'دهان وطلاء ديكوري',
      icon: Icons.format_paint_rounded,
      tint: Color(0xFF8E44AD),
      wash: Color(0xFFF4EAF8)
    ),
    (
      slug: 'plaster_drywall',
      name: 'جبس بورد وديكور',
      icon: Icons.layers_rounded,
      tint: Color(0xFFA9603C),
      wash: Color(0xFFF8EDE7)
    ),
    (
      slug: 'plumbing',
      name: 'سباكة وترصيص صحي',
      icon: Icons.plumbing_rounded,
      tint: Color(0xFF1F7FB8),
      wash: Color(0xFFE8F4FA)
    ),
    (
      slug: 'electrical',
      name: 'كهرباء وإنارة',
      icon: Icons.electrical_services_rounded,
      tint: Color(0xFFC9920F),
      wash: Color(0xFFFDF6E3)
    ),
    (
      slug: 'tiling_marble',
      name: 'بلاط وسيراميك ورخام',
      icon: Icons.grid_view_rounded,
      tint: Color(0xFF4A5568),
      wash: Color(0xFFEEF0F3)
    ),
    (
      slug: 'carpentry_aluminum',
      name: 'نجارة خشب وألمنيوم',
      icon: Icons.window_rounded,
      tint: Color(0xFF137E7E),
      wash: Color(0xFFE6F4F4)
    ),
    (
      slug: 'ironwork_welding',
      name: 'حدادة وتلحيم',
      icon: Icons.construction_rounded,
      tint: Color(0xFF5B6472),
      wash: Color(0xFFEFF0F2)
    ),
    (
      slug: 'waterproofing_insulation',
      name: 'عزل مائي وحراري',
      icon: Icons.water_drop_rounded,
      tint: Color(0xFF0E7C9B),
      wash: Color(0xFFE6F3F7)
    ),
    (
      slug: 'hvac_heating',
      name: 'تكييف وتدفئة',
      icon: Icons.ac_unit_rounded,
      tint: Color(0xFF2A7DE1),
      wash: Color(0xFFEAF2FE)
    ),
    (
      slug: 'epoxy_flooring',
      name: 'إيبوكسي وأرضيات',
      icon: Icons.texture_rounded,
      tint: Color(0xFF4C51A8),
      wash: Color(0xFFECECF9)
    ),
    (
      slug: 'landscaping_exterior',
      name: 'تهيئة خارجية وحدائق',
      icon: Icons.park_rounded,
      tint: Color(0xFF2E8B3D),
      wash: Color(0xFFE9F5EA)
    ),
    (
      slug: 'venetian_plaster',
      name: 'جبس فينيسي وستوكو',
      icon: Icons.brush_rounded,
      tint: Color(0xFFB5537A),
      wash: Color(0xFFFAEDF2)
    ),
    (
      slug: 'wallpaper',
      name: 'ورق جدران',
      icon: Icons.wallpaper_rounded,
      tint: Color(0xFF7A5AF8),
      wash: Color(0xFFF0EDFE)
    ),
  ];

  static String categoryName(String slug) {
    for (final c in categories) {
      if (c.slug == slug) return c.name;
    }
    return slug;
  }

  static IconData categoryIcon(String slug) {
    for (final c in categories) {
      if (c.slug == slug) return c.icon;
    }
    return Icons.handyman_rounded;
  }

  static Color categoryTint(String slug) {
    for (final c in categories) {
      if (c.slug == slug) return c.tint;
    }
    return const Color(0xFF5B6472);
  }

  static Color categoryWash(String slug) {
    for (final c in categories) {
      if (c.slug == slug) return c.wash;
    }
    return const Color(0xFFEFF0F2);
  }

  static String wilayaName(String id) {
    for (final w in wilayas) {
      if (w.id == id) return w.name;
    }
    return 'الجزائر';
  }
}