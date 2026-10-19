const authRedirectUrl = 'janitra://auth-callback/';
final _authRedirect = Uri.parse(authRedirectUrl);

bool isAuthCallback(Uri uri) =>
    uri.scheme == _authRedirect.scheme &&
    uri.host == _authRedirect.host &&
    uri.path == _authRedirect.path &&
    uri.userInfo.isEmpty &&
    !uri.hasPort;
