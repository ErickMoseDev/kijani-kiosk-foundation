# Cloud Service Model

The decision on which cloud service model to use depends on two foundational principles:

1. Who will manage the infrastructure (the service layer)
2. Where will the application run (the deployment location)

In order to choose the type of cloud service model to use, let's outline the pros and cons of each

1.  `Infrastructure as a Service (IaaS)`

| Pros (Advantages)                                          | Cons (Disadvantages)                                              |
| ---------------------------------------------------------- | ----------------------------------------------------------------- |
| Maximum Flexibility                                        | Requires specialized teams to maintain and operate                |
| Can be cost efficient when traffic is high                 | Takes time to provision and configure a fully working environment |
| Full access and total control of the system administration | Operational burden can be overwhelming                            |

2. `Platform as a Service (PaaS)`

| Pros (Advantages)                                                                   | Cons (Disadvantages)                                            |
| ----------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Focus is fully on developing the application                                        | Cases of Vendor lock in like Vercel                             |
| Encourages Faster development cycles                                                | You lack control of the underlying settings                     |
| Managed runtime means they handle everything out of the box and scalability is core | Costs can get out of hand of you don't optimize the application |

3. `Software as a Service (SaaS)`

| Pros (Advantages)                            | Cons (Disadvantages)                                                |
| -------------------------------------------- | ------------------------------------------------------------------- |
| Can be cheap when starting out               | Lack of control and fully relying on the provider                   |
| Can go to launch quite easily                | Can be hard to build on top due to the rigidity of the provider     |
| Zero maintenance of the underlying processes | The costs can rack up very fast when the application starts growing |

### Conclusion

Since Kijani Kiosk is a rapidly growing platform and is still at it's early stages of development, my advise would be to **choose a PaaS**.

This comes after a clear breakdown of the pros and cons of each model. While the IaaS appears to be quite lucrative, it can be operationally overwhelming to the engineering team and will be hard to balance development and managing the infrastructure.

By choosing a PaaS, you have the flexibility of choosing a platform that is closest to your kenyan customers hence reducing the speed latency. Example of a platform as a service in kenya is [Konza Cloud](https://konza.go.ke/konza-cloud/)

Working with a PaaS will also enable the engineering team to focus on the application and ship features faster.
