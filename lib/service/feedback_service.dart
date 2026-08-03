import 'package:miloka/service/supabase_service.dart';

class FeedbackService {
  static final _client = SupabaseService().client;

  static Future<void> submitFeedback({
    required String category,
    required String message,
    String contactEmail = '',
  }) async {
    final user = SupabaseService().getCurrentUser();

    await _client.from('feedbacks').insert({
      if (user != null) 'user_id': user.id,
      'category': category,
      'message': message,
      'contact_email': contactEmail,
    });

    try {
      await _client.functions.invoke(
        'send-feedback-email',
        body: {
          'category': category,
          'message': message,
          'contact_email': contactEmail,
          'user_id': user?.id,
        },
      );
    } catch (_) {}
  }
}
