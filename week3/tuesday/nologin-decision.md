# Should the service accounts use /usr/sbin/nologin or /bin/false?

Both achieve the same security goal of preventing interactive logins, but `/usr/sbin/nologin` is the preferred modern standard because it politely informs the user that the account is unavailable, whereas `/bin/false` simply exits silently. Using `nologin` makes troubleshooting easier for the kijani kiosk engineering team by clarifying that access was intentionally denied by policy rather than failing due to a system error.
