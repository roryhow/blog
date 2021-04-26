---
title: "Site Reliability Engineering - Embrace service unreliability to steer IT DevOps"
date: 2021-04-26T20:42:45+03:00
tags: [ "SRE", "DevOps", "IT", "e-commerce"]
---

It is understandable that many people who are responsible for digital services want the absolute bare minimum of downtime. Why would you want anything less than perfect? If your webshop isn't working, you aren't making money. This is completely true – but at what cost? The most stable service is the one that never changes: it must be built *perfectly* at the first time of asking, and it must never change from then onwards. The business-driven among us understand that this isn't an option; If you are sitting still, you are being left behind. So how do you balance development speed vs service stability? How do you ensure that your digital service stability isn't a bottleneck for the rest of your business operations? Service Reliability Engineering is a fantastic way to address this issue.

[Site Reliability Engineering (SRE)](https://sre.google) is a discipline of service management that attempts to marry service operations, infrastructure management and software engineering under a single job title. SRE is a Google-conceived set of principles and guidelines to facilitate more systematic management of digital services, which aims to create higher levels of confidence surrounding a service for developers, project managers, and upper management (hopefully also resulting in slightly lower blood pressures as a byproduct!). It can be quite logical to assume that these ways of working can only work at Google-sized companies, with many dedicated teams of SREs – but that doesn't have to be the case.

Here, we're going to make the case that applying SRE principles (albeit sparingly) in ecommerce services can actually have many of the same benefits that would be provided when utilising SRE practices at Google-scales. At Columbia Road, we utilise SRE within our Care operations, and we have found that introducing elements of SRE (and the corresponding cultural shifts that come along with it) allows for our clients' software teams to develop with confidence that in any unfortunate scenario, we have things covered.

![blog-sre-devops](https://www.columbiaroad.com/hubfs/Brand%20pictures%202019/blog-sre-devops.jpg)

## SRE extends DevOps

Many of the principles of SRE may seem familiar to those with experience in DevOps. If you're unfamiliar with DevOps, my colleague Mikko [wrote a blog post about how it can be used as an enabler for digital sales](https://www.columbiaroad.com/blog/devops-as-an-enabler-for-digital-sales) which serves as a nice introduction to the topic. We can even take the main topics in Mikko's blog post and match them to the corresponding SRE philosophy:

| **DevOps Principle**             | **DevOps Description**                                                                                                    | **SRE Implementation**                                                                                                                                                           |
|----------------------------------|---------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Principle of Flow                | Treat software development as a single value stream & remove bottlenecks where possible.                                  | Encourages automation of repetitive administrative tasks that introduce unnecessary overhead (known as toil).                                                                |
| Principle of Feedback            | Validate improvements to development processes by introducing feedback loops between different parts of development flow. | Operations is considered to be a software problem. Measurement of metrics that define customer happiness, such as availability, uptime using software development practices. |
| Principle of Continuous Learning | Create a culture where focus is on iteratively improving current processes.                                               | Continuous iteration on service reliability targets allows for better balancing of development speed vs. stability improvements.                                             |


Even though SRE is close to DevOps, it differs in the sense that it provides a more concrete set of implementation details and guidelines to get started with. To this end, we can consider DevOps and SRE to be complimentary: there are facets of DevOps that can be used in SRE processes, and vice-versa.

## SLAs, SLOs and SLIs, oh my!

SRE allows for development teams to be able to set targets for service unreliability. Service unreliability in this context dictates how much you can afford your service to operate in a degraded state (think how long you can tolerate downtime etc). This might already be familiar to those who have worked with services that are managed under a Service Level Agreement (SLA), which outlines contractual requirements for common metrics such as service availability. In SRE, we extend this philosophy, but instead use service targets to dictate the speed in which a service is developed. A target for service reliability is called a Service-Level Objective (SLO). For example, a common SLO may look as follows:

_99.9% of all GET requests to service <X> will result in a response code of the range of 200-400._

In the above SLO we are measuring request/response availability as an indicator of service reliability. The availability in this context is known as a Service Level Indicator, or SLI. We can use a range of different SLIs to help us formulate targets (SLOs), which in turn dictate the speed and structure of development based on whether SLO targets are met over a given time period (usually measured over the past rolling month). It is important to note that this 0.1% threshold of request failures is a kind of budget – so let's use it! It's fine if we ship some things that don't work perfectly, if it allows us to develop features more quickly, and doesn't bring a significant negative impact to the end-user experience. This is what it means to embrace service unreliability.

But this begs the question, if we have SLA in place already in a service maintenance contract, why do we need to do the same thing again for the development team? The reasoning behind this is that SLOs help you to stay within your SLA targets. While it is generally speaking "acceptable" to miss an SLO target for a given month (with consequences, however), it is not considered acceptable to miss an SLA target, which often comes with a financial penalty as a result. So with this in mind, we can consider SLOs to be a tool to help software teams stay within the bounds of an SLA.

## How to start setting service performance objectives?

Broadly speaking, any performance indicator used should **directly correspond to the user experience**. After all, your users won't notice (or care) if your server CPU is running at a 20% or 80% utilisation rate. They do, however, care when the performance of a service is degraded due to >95% CPU utilisation rate and no configured server autoscaling policy.

With this in mind, it's important to consider the following: What makes the user journey of your service a "happy" one? If you're wanting to set performance targets for a webshop checkout funnel, perhaps you consider it most important that request failures are minimised (if a request fails during payment, and your users aren't sure if an order has been placed, they're a bit less likely to return in the future!). Maybe you operate a webshop where often many items are added to a shopping cart in quick succession: in this case, you might want to set a target for request latency. It's also totally plausible (and even encouraged) to have multiple SLOs in place that collectively provide a summary of the happiness of the users of your service.

However, for an SLO to be valid, it needs to have a concrete target value that should be met each month. In order to be able to establish such a target, we need to be able to find some historic (or current) data that shows to us what kind of targets might be feasible.

## Data is King

Once you've considered the most important areas of your user journey, and what areas of your service encompass your user happiness, you'll need to find some data to help you track those SLOs.

1.  Have you been collecting any historic data that can be used to help track your SLOs?
2.  Where might you be able to collect such data to help you track your SLIs?

– As usual, we want to capture this data in such a way that is as close as possible to representing the user experience in the wild. This means that collecting data from a client (i.e mobile application) is usually more valuable than data collected on the server.

If you're able to refer to historic data, then great! This means that you have a baseline for setting your SLO targets. You always want to make sure that any target that you set for an SLO is fundamentally achievable. People are much less likely to take an SLO seriously if they know that they are going to miss it at the first time of asking.

If you don't have any historic data, then this isn't a problem either. However, it's recommended that you begin collecting data straight away, and then set an initial SLO target after a period of time has passed (usually on the scope of a couple months), to help you set more realistic availability targets.

## Iterate, Iterate, Iterate

After you set an SLO for the first time, it's very unlikely that this will be the best _actua_l target for your development team. It may be that it's too relaxed, and your users are unhappy with your service even though you're meeting your SLO targets. Or conversely, perhaps your SLO targets are too strict, and your users are happy with your service stability, even though SLOs have been missed?

For any service, we want to aim for stability, but only _just about_ enough stability. It is only necessary for any digital service to be "good enough". Over-optimisation of processes and services will only introduce unnecessary overhead, which is costly and inefficient. If your users are happy with your service, then you should be as well (even if it's not working perfectly!).

So take the time to review your SLOs regularly. Are they accurately capturing the customer happiness in the most important parts of your user journeys? Are there any areas that are missed that shouldn't be? Are your users happy when your SLOs are satisfied? Don't be afraid to make changes! SLOs are intended to be improved continuously.

## Failure is normal, and no-one is to blame for that

Ultimately, any SLOs that you define require the true backing of your organisation. There are many different reasons behind this:

#### Missing SLO targets & consequences

_"If an SLO can be missed without consequences to development processes, there's little motivation to meet it in the first place."_

When an SLO is missed, improvement measures must be embraced by developers and management, alike. To freeze feature development in favour of maintenance and stability fixes may introduce delays to a tight release schedule, but it ultimately provides a benefit to the user in the form of a stable, fully functional service.

#### Acceptance of failure

_"100% availability may sound like an attractive target for service uptime, but it's very rarely the correct choice."_

Any change to code introduces a risk of failure, so a 100% availability target would result in effectively no new feature development. In addition, many ecommerce stores integrate with a range of external services and providers, each of which cannot possibly provide 100% availability, therefore eradicating the possibility of a 100% availability target for anything operating downstream.

#### Maintenance as the most important feature

_"You may be able to push out more features if you choose to neglect maintainability, but this introduces a technical debt that you will need to repay eventually."_

Features are great, and they can often give you the edge over the competition! But if your services are making your customers unhappy in other areas, then they're less likely to spend their money with you. Treating maintenance as a first-class citizen during team task prioritisation allows for a more healthy balance of development velocity to service stability.

## But why does this matter for my ecommerce store?

I'm sure that few people would disagree with the principles that are outlined here. But how can this tie to an ecommerce store? There is no direct link to ecommerce for these principles; they are general to any digital service. But in ecommerce, where the user experience directly corresponds to the revenue that your company is generating, embracing a customer experience-first approach to service reliability can direct you towards operating "good enough" services. After all, it doesn't matter if you create a webshop that only experiences downtime for 5 seconds per year in the middle of the night (losing you next to nothing in revenue) if it costs you hundreds of developer hours to reach that point. This is where SRE shines – it doesn't force you to go overboard, it simply encourages you to embrace a few principles:

- Service unreliability shouldn't be shunned, it should be embraced.
- Service unreliability should be measured by the end-user experience directly.
- Service unreliability can then be used to formulate your development workflows (measuring the speed of development vs. stability).

Once these philosophies are embraced by your organisation, everything else will start to fall into place.
