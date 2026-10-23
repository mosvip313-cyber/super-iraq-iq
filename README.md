# سوبر العراق IQ — المرحلة الأولى

واجهة أولية تفاعلية مستوحاة من توزيع شاشة SUPER POS FE التي زودني بها المستخدم، مع تنفيذ مستقل.

## التشغيل
1. فك ضغط الملف.
2. افتح `apps/admin-web/index.html` باستخدام Microsoft Edge أو Google Chrome.
3. البيانات التجريبية تحفظ محلياً في المتصفح باستخدام `localStorage`.

## الموجود حالياً
- واجهة نقطة البيع RTL.
- سلة مشتريات مع زيادة/تقليل الكمية، خصم، طرق دفع، وحفظ فاتورة محلية.
- إدارة المنتجات وإضافة/تعديل/حذف.
- بحث بالاسم والباركود، فئات، استيراد/تصدير CSV المتوافق مع Excel.
- صفحة عملاء أولية، تقارير وسجل فواتير، هيكل أولي للموردين والخزنة والمستخدمين والإعدادات.

## حدود النسخة
هذه نسخة أولية للواجهة وليست نظاماً جاهزاً للاستخدام التجاري. التخزين داخل المتصفح وليس SQLite، ولا توجد مزامنة بين الأجهزة أو صلاحيات حقيقية أو طباعة فواتير متكاملة أو تثبيت Windows EXE. استيراد CSV مبسط. لا تستخدمها لحسابات تجارية حقيقية قبل التطوير والاختبار.

## المرحلة التالية
- نقل التخزين إلى SQLite محلياً.
- إنشاء تطبيق Electron قابل للتثبيت على Windows.
- اختبارات المخزون والفواتير والديون والمردودات والنسخ الاحتياطي.
- مزامنة الفروع والصلاحيات والتقارير المتقدمة.


## المرحلة 14 — المحاسبة والورديات
راجع الملف: README-المرحلة-الرابعة-عشرة-المحاسبة-والورديات.txt


## المرحلة 26 — تقوية الخادم وسجل الأمان
راجع الملف `README-المرحلة-السادسة-والعشرون-تقوية-الخادم-وسجل-الأمان.txt` قبل تشغيل الخادم. تتضمن هذه المرحلة تحديد حجم الطلبات ومعدلاتها، والتحقق من رموز الفروع، وتسجيل أحداث المزامنة في `security_audit_log`. هذه ليست بديلاً عن مصادقة الموظفين المركزية وفرض الصلاحيات على مستوى كل عملية في الخادم.


## المرحلة 27 — المزامنة المركزية الآمنة
راجع `README-المرحلة-السابعة-والعشرون-المزامنة-المركزية.txt` وطبّق `server/supabase-phase27.sql` في Supabase قبل تشغيل إصدار الخادم الجديد.

## Phase 28 — Financial reporting improvements
Adds period-based sales returns and operating-expense totals to the reports screen and CSV summary, plus an explicitly estimated operating-net figure. The estimate is not a certified accounting statement; returned-stock cost treatment still needs a formal accounting workflow. See `README-المرحلة-الثامنة-والعشرون-التقارير-المالية.txt`.

## المرحلة 29 — القيود اليومية المزدوجة
- إضافة إدخال يدوي لقيود يومية مدين/دائن متوازنة.
- إضافة عرض القيود وميزان مراجعة مبسط وتصدير CSV.
- القيود لا تُنشأ تلقائياً من المعاملات التشغيلية، لذا لا يعتبر هذا النظام دفتر أستاذ متكاملاً أو بديلاً عن مراجعة محاسب.

## المرحلة 31 — الصندوق متعدد العملات

أُضيف سجل حركة للصندوق يدعم الدينار العراقي والدولار الأمريكي، مع عرض رصيد مستقل لكل عملة، وحفظ المبلغ الأصلي وسعر الصرف والقيمة المقابلة بالدينار. راجع ملف `README-المرحلة-الحادية-والثلاثون-الصندوق-متعدد-العملات.txt` للتفاصيل والحدود المعروفة. لم يتم اختبار هذه المرحلة على خادم إنتاج.


## Phase 34 — One-screen cashier layout
- Reworked POS grid to fit the desktop viewport with no page-level vertical scrolling while the cashier page is open.
- Compressed customer, sale mode, currency, payment, discount, totals, paid/remaining, and checkout controls to keep them visible together.
- Cart rows and product grid scroll internally when content exceeds available space.
- Preserved existing sales calculation and save handlers; mobile layout remains vertically scrollable.
- UI/CSS change only; validate in the target browser and screen resolution before production use.


## المراحل 43–50 — حزمة تقوية متعددة الأجهزة
راجع `README-phase43-50-hardening.txt`، وطبّق `server/supabase-phase43-50-hardening.sql` قبل نشر كود الخادم المحدّث. تشمل الحزمة رمز جهاز في أرقام الفواتير والتحقق الخادمي من رصيد المخزون عند قبول البيع. لا تُعتمد للإنتاج قبل اختبار قاعدة البيانات الفعلية وتوحيد الشراء والمرتجعات والجرد والتعديلات عبر واجهات خادمية.
