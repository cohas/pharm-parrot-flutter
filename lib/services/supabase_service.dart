import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient client;
  SupabaseService(this.client);

  Future<dynamic> rpc(String fn, Map<String, dynamic> params) async {
    final res = await client.rpc(fn, params: params);
    return res; // can be List or Map or primitive depending on function
  }
}
