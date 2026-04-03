const currentUgcTermsVersion = '2026-04-03';

enum UserReportReason {
  harassment('harassment'),
  hate('hate'),
  sexualContent('sexual_content'),
  violence('violence'),
  spam('spam'),
  impersonation('impersonation'),
  other('other');

  const UserReportReason(this.storageValue);

  final String storageValue;
}
