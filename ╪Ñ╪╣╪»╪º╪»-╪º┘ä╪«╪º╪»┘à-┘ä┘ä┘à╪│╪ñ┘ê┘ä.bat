@echo off
chcp 65001 >nul
cd /d "%~dp0server"
echo =============================================
echo   إعداد خادم سوبر العراق IQ - للمسؤول فقط
echo =============================================
where node >nul 2>nul
if errorlevel 1 (
  echo يلزم تثبيت Node.js إصدار 20 أو أحدث من الموقع الرسمي.
  echo https://nodejs.org/
  pause
  exit /b 1
)
if not exist .env (
  copy .env.example .env >nul
  echo تم إنشاء server\.env من القالب.
  echo افتح الملف وأدخل بيانات Supabase وOpenAI ورمز الفرع.
  echo لا ترسل ملف .env للزبائن ولا ترفعه إلى الإنترنت.
  notepad .env
  pause
)
call npm install
if errorlevel 1 (echo فشل تثبيت المكتبات.& pause & exit /b 1)
call npm start
pause
