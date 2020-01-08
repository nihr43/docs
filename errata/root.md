# Reflections on the State of the Art

I've now spent a decade exploring various solutions to [the root problem](https://papers.freebsd.org/2000/phk-jails.files/sane2000-jail.pdf), and more broadly, trying to run software and store data on more than one computer.

Given my experiences I assert the following:

- we still do not know how to safely run more than one program on a computer
- we barely know how to use more than one computer
- the filesystem is the wrong layer of abstraction for network file storage
- OS virtualization is the only rational option
- seek to apply functional programming paradigms to infrastructure and system architecture
- seek apply the unix philosophy to infrastructure and system architecture
- distributed authority and trust remain unsolved issues

---

*authority*

Say we choose to adopt gitops to address increasing challenges in managing a complex environment of heterogeneous databases, app servers, firewalls, public/private lan segments...  We move services one-by-one to a push-button, infrastructure-as-a-service paradigm.  Even the firewall rules are templated, version controlled, and continuously deployed by a pipeline.  Our entire infrastructure, save the contents of the databases, is represented by yaml files in a github repository.  Fantastic!

Hold on.  Now our github passwords are effectively root passwords for the entire infrastucture.  We may have addressed our managment overhead, but we've applified the "root" problem.  In fact, whats the point of the firewalls if they're being provisioned from the same repository as the databases?

I don't yet know the answers to these questions.  I lean towards "yeah, but its worth the tradeoff".  Version control is more transparent than a lack thereof, and some of these issues can be mitigated with 2fa and smart policy.  Similar arguments can be raised for software itself: what if a core committer's pgp key gets compromised?

---

*to be continued*
