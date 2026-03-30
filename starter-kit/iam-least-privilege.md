# Identity Access Management

Identity and Access Management (IAM) is a framework of policies, processes, and technologies that ensures the right individuals have the appropriate level of access to the right resources at the right time. In cloud environments, IAM is the primary mechanism for controlling **who** can do **what** on **which** resources.

For Kijani Kiosk, IAM is critical because the platform handles sensitive customer data such as personal details, order history, and payment information. A misconfigured permission can expose this data or allow unauthorized actions that compromise the integrity of the application.

## The Principle of Least Privilege

The principle of least privilege states that every user, service, or system component should be granted only the minimum permissions required to perform its intended function and nothing more.

This principle is important because:

- It limits the blast radius in case of a security breach
- It reduces the risk of accidental or malicious misuse of resources
- It simplifies auditing and compliance

## Kijani Kiosk Customer Access Policy

Below is a role and policy design for how **customers** interact with the Kijani Kiosk application. This follows the principle of least privilege by granting customers access only to their own data and the actions they need to perform.

### Role: `Customer`

| Attribute        | Value                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| Role Name        | `kijani-customer`                                                           |
| Description      | End-user who browses products, places orders, and manages their own account |
| Trust Boundary   | Authenticated via the application (email/password or OAuth)                 |
| Session Lifetime | Short-lived tokens (e.g. 1 hour access token, 7 day refresh)                |

### Policy: `CustomerAccessPolicy`

The policy is broken down by resource and the actions a customer is allowed or denied.

#### Allowed Actions

| Resource            | Allowed Actions                          | Scope                        |
| ------------------- | ---------------------------------------- | ---------------------------- |
| **Own Profile**     | Read, Update                             | Only their own account       |
| **Product Catalog** | Read (browse, search, view details)      | All published products       |
| **Shopping Cart**   | Create, Read, Update, Delete items       | Only their own cart          |
| **Orders**          | Create (place order), Read (view status) | Only their own orders        |
| **Payment Methods** | Create, Read, Delete                     | Only their own saved methods |
| **Reviews/Ratings** | Create, Read, Update, Delete             | Only their own reviews       |
| **Support Tickets** | Create, Read                             | Only their own tickets       |

#### Denied Actions

| Resource                 | Denied Actions                                        | Reason                                     |
| ------------------------ | ----------------------------------------------------- | ------------------------------------------ |
| **Other Users' Data**    | Read, Update, Delete                                  | Customers must never access other accounts |
| **Admin Dashboard**      | All                                                   | Reserved for internal staff                |
| **Product Management**   | Create, Update, Delete                                | Only merchants/admins manage inventory     |
| **Order Fulfillment**    | Update (status changes, cancellations after dispatch) | Controlled by operations team              |
| **System Configuration** | All                                                   | Infrastructure-level access only           |

### Enforcement Strategy

1. **Authentication** — Every request from a customer must carry a valid, signed token (e.g. JWT). Unauthenticated requests are rejected before reaching any business logic.
2. **Resource-level Authorization** — API endpoints must verify that the authenticated user owns the resource they are attempting to access. For example, `GET /orders/{id}` must confirm the order belongs to the requesting customer.
3. **Input Validation** — All customer-facing inputs are validated and sanitized at the API boundary to prevent injection attacks or privilege escalation.
4. **Rate Limiting** — Customer endpoints should be rate-limited to prevent abuse such as brute-force attacks or scraping of the product catalog.
5. **Audit Logging** — All access attempts, especially denied ones, should be logged for monitoring and incident response.

### Example: Policy as JSON (Cloud-Agnostic Pseudocode)

```json
{
	"roleName": "kijani-customer",
	"statements": [
		{
			"effect": "Allow",
			"actions": ["profile:read", "profile:update"],
			"resources": ["arn:kijani:profile:${self.userId}"]
		},
		{
			"effect": "Allow",
			"actions": ["catalog:read"],
			"resources": ["arn:kijani:products:*"]
		},
		{
			"effect": "Allow",
			"actions": [
				"cart:create",
				"cart:read",
				"cart:update",
				"cart:delete"
			],
			"resources": ["arn:kijani:cart:${self.userId}"]
		},
		{
			"effect": "Allow",
			"actions": ["orders:create", "orders:read"],
			"resources": ["arn:kijani:orders:${self.userId}/*"]
		},
		{
			"effect": "Deny",
			"actions": ["*"],
			"resources": ["arn:kijani:admin:*", "arn:kijani:system:*"]
		}
	]
}
```

The `${self.userId}` variable ensures that resource access is always scoped to the authenticated customer's own data, making it impossible for one customer to access another's resources regardless of how the request is constructed.

## Conclusion

By defining a clear IAM policy for Kijani Kiosk customers, the engineering team ensures that even as the platform grows and new features are added, the security posture remains strong. Every new endpoint or resource introduced should be evaluated against the principle of least privilege: grant only what is needed, deny everything else by default. This approach protects customer data, reduces operational risk, and builds the trust that is essential for an e-commerce platform handling real transactions.
