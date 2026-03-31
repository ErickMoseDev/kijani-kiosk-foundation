# The Three Ways

For the engineers at Kijani Kiosk to become a high performing team, the three ways of DevOps should be their guiding mantra as it allows for them to quickly get in flow, constantly receive and implement feedback and to accelerate their learning from the challenges they face. This section will explore the three ways and provide a basis for the team

## Flow

In order for Kijani Kiosk to get to optimal flow state, the process of getting from idea -> Deploy -> Learning should be frictionless. A proper flow state involves having the system work in your favor as opposed to against you. The simple delivery pipeline outlined below represents optimizations that can be made along each stage.

- `Idea` - Once an idea of a feature has been discussed and outlined, the next step is transforming this into actual code
- `Code` - To prevent friction at this stage, the team should utilize tools like [Linear](https://linear.app/) for project management and assigning of tasks. This ensures that all the engineers have been properly allocated tasks and not conflicting with each other on what to do. Utilize tools like `git` and `Github` for version control and collaboration. Follow proper branch and commit guidelines and conventions i.e [conventionalcommits](https://www.conventionalcommits.org/en/v1.0.0/).
- `Build -> Test -> Package -> Deploy` - Set up a series of automated steps that will be triggered as the developers keep pushing new features. Automation at this stage is critical as it helps offload the manual process of approval from team members. This is referred to as a `CI/CD pipeline`. A healthy pipeline means the team can move from development to production very quickly and speed is the only moat in this rapidly evolving tech industry.

## Feedback Loop

While speed is the ultimate competitive advantage, having a system that amplifies feedback loops means that the team at Kijani Kiosk will be able move in the right direction when they encounter challenges. This means that at key points of the development process, setting up automated tests when code is committed, utilizing code review tools such as [CodeRabbit](https://www.coderabbit.ai/) that catch any issues early before finally submitting it to a human reviewer will improve the overall process. Gains will be much more visible as the system grows.

### Learning

This final way is ultimately the most important when it comes to ensuring that mistakes are not repeated and the engineers can move forward as a team. Gathering all the data from the flow state and the feedback loops set along the dev process will help in establishing a blameless culture and foster continued growth. Adopting practices like stress testing the application in controlled environments will also help prevent prevent production incidents.
