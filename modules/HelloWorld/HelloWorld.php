
<?php

function e($v) { return htmlspecialchars($v ?? '', ENT_QUOTES, 'UTF-8'); }

// File where submissions are stored (CSV)
$csvFile = __DIR__ . '/submissions.csv';

$errors = [];
$data = [
    'test_date' => '',
    'unit_type' => '', // بالصفحة أو الثمن
    'from' => '',
    'to' => '',
    'tanbihat' => [],
    'ghunna' => [],
    'madood' => [],
    'qalqalah' => [],
    'saved' => '',
    'notes' => ''
];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Collect
    $data['test_date'] = $_POST['test_date'] ?? '';
    $data['unit_type'] = $_POST['unit_type'] ?? '';
    $data['from'] = $_POST['from'] ?? '';
    $data['to'] = $_POST['to'] ?? '';
    $data['tanbihat'] = $_POST['tanbihat'] ?? [];
    $data['ghunna'] = $_POST['ghunna'] ?? [];
    $data['madood'] = $_POST['madood'] ?? [];
    $data['qalqalah'] = $_POST['qalqalah'] ?? [];
    $data['saved'] = $_POST['saved'] ?? '';
    $data['notes'] = $_POST['notes'] ?? '';

    // Basic validation
    if (empty($data['test_date'])) $errors[] = 'الرجاء اختيار تاريخ الاختبار.';
    if (!in_array($data['unit_type'], ['page','eighth'])) $errors[] = 'اختر نوع الوحدة (بالصفحة أو بالثمن).';
    if ($data['from'] === '' || $data['to'] === '') $errors[] = 'اختر مقدار الحفظ من وإلى.';
    if (is_numeric($data['from']) && is_numeric($data['to']) && (int)$data['from'] > (int)$data['to']) $errors[] = 'قيمة "من" يجب أن تكون أقل أو تساوي "إلى".';
    if (!in_array($data['saved'], ['saved','not_saved'])) $errors[] = 'اختر حالة الحفظ.';

    if (empty($errors)) {
        // Save to CSV (append)
        $row = [
            $data['test_date'],
            $data['unit_type'],
            $data['from'],
            $data['to'],
            implode('|', $data['tanbihat']),
            implode('|', $data['ghunna']),
            implode('|', $data['madood']),
            implode('|', $data['qalqalah']),
            $data['saved'],
            str_replace("\n", " ", $data['notes'])
        ];
        $fp = fopen($csvFile, 'a');
        if ($fp) {
            fputcsv($fp, $row);
            fclose($fp);
        }

        // Show success and clear fields
        $success = 'تم حفظ السجل بنجاح.';
        $data = array_fill_keys(array_keys($data), '');
    }
}

?>
<style>
@import url('https://fonts.googleapis.com/css2?family=Cairo:wght@300;400;600;700&display=swap');

:root {
    --primary: #0f5132;
    --secondary: #198754;
    --accent: #d4af37;
    --bg: #f4f8f6;
    --card-bg: #ffffff;
    --danger: #dc3545;
    --success: #198754;
}

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    font-family: 'Cairo', sans-serif;
    background: linear-gradient(rgba(15,81,50,0.85), rgba(15,81,50,0.85)),
                url('https://www.transparenttextures.com/patterns/arabesque.png');
    background-color: var(--bg);
    color: #333;
    direction: rtl;
    padding: 20px;
}

h1 {
    text-align: center;
    color: white;
    margin-bottom: 5px;
}

h3 {
    text-align: center;
    color: var(--accent);
    font-weight: 400;
    margin-bottom: 30px;
}

form {
    background: var(--card-bg);
    max-width: 900px;
    margin: auto;
    padding: 30px;
    border-radius: 16px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.15);
}

label {
    font-weight: 600;
    margin-top: 15px;
    display: block;
}

input, select, textarea {
    width: 100%;
    padding: 10px 12px;
    margin-top: 6px;
    border-radius: 8px;
    border: 1px solid #ccc;
    font-family: 'Cairo', sans-serif;
    transition: 0.3s;
}

input:focus, select:focus, textarea:focus {
    outline: none;
    border-color: var(--secondary);
    box-shadow: 0 0 0 2px rgba(25,135,84,0.2);
}

.row {
    display: flex;
    gap: 15px;
}

.col {
    flex: 1;
}

fieldset {
    margin-top: 20px;
    border-radius: 12px;
    border: 1px solid #ddd;
    padding: 15px;
}

legend {
    padding: 0 10px;
    font-weight: 600;
    color: var(--primary);
}

.checkbox-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 10px;
}

.small {
    font-weight: normal;
    font-size: 14px;
}

.actions {
    margin-top: 25px;
    text-align: center;
}

button {
    background: var(--secondary);
    color: white;
    border: none;
    padding: 10px 25px;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 600;
    transition: 0.3s;
    margin: 5px;
}

button:hover {
    background: var(--primary);
}

button[type="reset"] {
    background: #6c757d;
}

.error {
    background: #f8d7da;
    color: var(--danger);
    padding: 15px;
    border-radius: 8px;
    max-width: 900px;
    margin: 10px auto;
}

.success {
    background: #d1e7dd;
    color: var(--success);
    padding: 15px;
    border-radius: 8px;
    max-width: 900px;
    margin: 10px auto;
    text-align: center;
    font-weight: 600;
}

table {
    width: 100%;
    margin-top: 20px;
    border-collapse: collapse;
    background: white;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 5px 15px rgba(0,0,0,0.1);
}

thead {
    background: var(--primary);
    color: white;
}

th, td {
    padding: 10px;
    text-align: center;
}

tbody tr:nth-child(even) {
    background: #f2f2f2;
}

tbody tr:hover {
    background: #e9f7ef;
}

/* Responsive */
@media (max-width: 768px) {
    .row {
        flex-direction: column;
    }

    form {
        padding: 20px;
    }

    table {
        font-size: 12px;
    }
}
</style>
<body>
    <h1>جدول متابعة الحفظ (بالصفحة أو بالثمن)</h1>
    <h3>المدرس : محمد الأحول</h3>

    <?php if (!empty($errors)): ?>
        <div class="error">
            <ul>
                <?php foreach ($errors as $err): ?>
                    <li><?php echo e($err); ?></li>
                <?php endforeach; ?>
            </ul>
        </div>
    <?php endif; ?>

    <?php if (!empty($success)): ?>
        <div class="success"><?php echo e($success); ?></div>
    <?php endif; ?>

    <form method="post">
        <label>تاريخ الاختبار</label>
        <input type="date" name="test_date" value="<?php echo e($data['test_date']); ?>" />

        <label>(بالصفحة أو الثمن)</label>
        <select name="unit_type">
            <option value="">-- اختر --</option>
            <option value="page" <?php echo $data['unit_type']==='page'? 'selected':''; ?>>بالصفحة</option>
            <option value="eighth" <?php echo $data['unit_type']==='eighth'? 'selected':''; ?>>بالثمن</option>
        </select>

        <label>مقدار الحفظ من.... إلى .....</label>
        <div class="row">
            <div class="col">
                <select id="from" name="from" onchange="syncFromTo()">
                    <option value="">من</option>
                    <?php for ($i=1;$i<=30;$i++): ?>
                        <option value="<?php echo $i; ?>" <?php echo ($data['from']==(string)$i)?'selected':''; ?>><?php echo $i; ?></option>
                    <?php endfor; ?>
                </select>
            </div>
            <div class="col">
                <select id="to" name="to">
                    <option value="">إلى</option>
                    <?php for ($i=1;$i<=30;$i++): ?>
                        <option value="<?php echo $i; ?>" <?php echo ($data['to']==(string)$i)?'selected':''; ?>><?php echo $i; ?></option>
                    <?php endfor; ?>
                </select>
            </div>
        </div>

        <fieldset>
            <legend>التنبيهات (اختر ما ينطبق)</legend>
            <div class="checkbox-grid">
                <?php for ($i=1;$i<=6;$i++): ?>
                    <label class="small"><input type="checkbox" name="tanbihat[]" value="اختيار <?php echo $i; ?>" <?php echo in_array("اختيار $i", $data['tanbihat']) ? 'checked':''; ?> /> اختيار <?php echo $i; ?></label>
                <?php endfor; ?>
            </div>
        </fieldset>

        <fieldset>
            <legend>الغنة (اختر ما ينطبق)</legend>
            <div class="checkbox-grid">
                <?php for ($i=1;$i<=6;$i++): ?>
                    <label class="small"><input type="checkbox" name="ghunna[]" value="اختيار <?php echo $i; ?>" <?php echo in_array("اختيار $i", $data['ghunna']) ? 'checked':''; ?> /> اختيار <?php echo $i; ?></label>
                <?php endfor; ?>
            </div>
        </fieldset>

        <fieldset>
            <legend>المدود (اختر ما ينطبق)</legend>
            <div class="checkbox-grid">
                <?php for ($i=1;$i<=6;$i++): ?>
                    <label class="small"><input type="checkbox" name="madood[]" value="اختيار <?php echo $i; ?>" <?php echo in_array("اختيار $i", $data['madood']) ? 'checked':''; ?> /> اختيار <?php echo $i; ?></label>
                <?php endfor; ?>
            </div>
        </fieldset>

        <fieldset>
            <legend>القلقلة (اختر ما ينطبق)</legend>
            <div class="checkbox-grid">
                <?php for ($i=1;$i<=6;$i++): ?>
                    <label class="small"><input type="checkbox" name="qalqalah[]" value="اختيار <?php echo $i; ?>" <?php echo in_array("اختيار $i", $data['qalqalah']) ? 'checked':''; ?> /> اختيار <?php echo $i; ?></label>
                <?php endfor; ?>
            </div>
        </fieldset>

        <label>حفظ/لم يحفظ</label>
        <label class="small"><input type="radio" name="saved" value="saved" <?php echo ($data['saved']==='saved')?'checked':''; ?> /> حفظ</label>
        <label class="small"><input type="radio" name="saved" value="not_saved" <?php echo ($data['saved']==='not_saved')?'checked':''; ?> /> لم يحفظ</label>

        <label>ملاحظات عامة</label>
        <textarea name="notes" rows="4"><?php echo e($data['notes']); ?></textarea>

        <div class="actions">
            <button type="submit">حفظ</button>
            <button type="reset">إعادة</button>
        </div>
    </form>

    <hr />
    <h4>سجلات محفوظة (من ملف CSV)</h4>
    <?php if (file_exists($csvFile)): ?>
        <table border="1" cellpadding="6" cellspacing="0">
            <thead>
                <tr>
                    <th>تاريخ</th><th>وحدة</th><th>من</th><th>إلى</th><th>تنبيهات</th><th>غنة</th><th>مدود</th><th>قلقلة</th><th>حالة</th><th>ملاحظات</th>
                </tr>
            </thead>
            <tbody>
                <?php
                if (($handle = fopen($csvFile, 'r')) !== false) {
                    while (($row = fgetcsv($handle)) !== false) {
                        echo '<tr>';
                        foreach ($row as $cell) {
                            echo '<td>' . e($cell) . '</td>';
                        }
                        echo '</tr>';
                    }
                    fclose($handle);
                }
                ?>
            </tbody>
        </table>
    <?php else: ?>
        <p>لا توجد سجلات محفوظة حتى الآن.</p>
    <?php endif; ?>

</body>
