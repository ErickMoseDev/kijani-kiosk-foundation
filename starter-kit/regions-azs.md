# Regions and Availability Zones

In order to have a good and fast experience for the Kijani Kiosk application, the engineering team needs to understand the following principles:

- Choose the region closest to your primary users
- Deploy across multiple availability zones for production systems
- Use multi-region architectures only when business continuity requirements justify the added complexity

## Region closest to your primary users

This is a geographical area where there are multiple data centers. When choosing which cloud provider to use, the provider with the closest region to your users is most preferred. This helps in reducing the latency and in turn results in an enhanced experience for your customers

## Multiple availability zones for production systems

An Availability Zone (AZ) is one or more data centers within a Region. For production systems, it is advised to not rely on only one zone. This is largely because of factors such as:

- A power outage affecting a single data center
- A networking failure within one facility
- Hardware failure in a server cluster

Systems designed across multiple zones can continue operating even if one of these failures occurs.

## Multi-region architectures

This should be a last resort and should only be considered if the company can justify the need to use it. This is because it adds onto the operational complexities and can be quite expensive. This should only be considered when the stakes are high

# Conclusion

For Kijani Kiosk, the immediate priority should be selecting a cloud provider with a region in or near East Africa to serve the Kenyan customer base with the lowest possible latency. A provider like [Konza Cloud](https://konza.go.ke/konza-cloud/) or any global provider with an Africa-based region would be ideal.

At the current stage, deploying across at least two availability zones within that region is strongly recommended for the production environment. This ensures that a single data center failure does not translate into downtime for customers, providing the resilience expected of a growing e-commerce platform without introducing unnecessary complexity.

Multi-region architecture should remain off the table for now. The added operational cost and complexity are not justified until Kijani Kiosk expands to serve users across significantly different geographies or has strict regulatory and business continuity requirements that demand it. As the platform matures and the user base grows beyond Kenya, revisiting a multi-region strategy will become a worthwhile conversation.
