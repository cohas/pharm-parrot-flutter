class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://upiwjinpuzfgkafbsjab.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVwaXdqaW5wdXpmZ2thZmJzamFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTc3NTUxODksImV4cCI6MjAzMzMzMTE4OX0.YSN1mgHyTxuXagXMMuJXJXdBJrI6vh9qbTWKEfifBxk',
  );
}
