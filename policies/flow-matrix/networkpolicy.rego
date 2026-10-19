# Vérifie que chaque NetworkPolicy n'ouvre que des flux présents dans la
# matrice de flux (risque résiduel R1 du livrable 9).
package main

import rego.v1

is_netpol if input.kind == "NetworkPolicy"

dest_app := input.spec.podSelector.matchLabels.app

flow_allowed(src_ns, src_app, port) if {
	some f in data.flows
	f.to.namespace == input.metadata.namespace
	f.to.app == dest_app
	f.from.namespace == src_ns
	f.from.app == src_app
	f.port == port
}

# Une règle d'entrée sans « from » laisse tout le monde entrer.
deny contains msg if {
	is_netpol
	some rule in input.spec.ingress
	not rule.from
	msg := sprintf("%s/%s : règle d'entrée ouverte à tous (pas de 'from')", [input.metadata.namespace, input.metadata.name])
}

deny contains msg if {
	is_netpol
	some rule in input.spec.ingress
	some peer in rule.from
	peer.ipBlock
	msg := sprintf("%s/%s : ipBlock interdit, utiliser des sélecteurs de namespace et de pod", [input.metadata.namespace, input.metadata.name])
}

deny contains msg if {
	is_netpol
	some rule in input.spec.ingress
	some peer in rule.from
	not peer.ipBlock
	some p in rule.ports
	src_ns := object.get(peer, ["namespaceSelector", "matchLabels", "kubernetes.io/metadata.name"], input.metadata.namespace)
	src_app := object.get(peer, ["podSelector", "matchLabels", "app"], "*")
	not flow_allowed(src_ns, src_app, p.port)
	msg := sprintf("%s/%s : flux %s/%s -> %s:%v absent de la matrice de flux", [input.metadata.namespace, input.metadata.name, src_ns, src_app, dest_app, p.port])
}

# Une règle sans port ouvre tous les ports.
deny contains msg if {
	is_netpol
	some rule in input.spec.ingress
	rule.from
	not rule.ports
	msg := sprintf("%s/%s : règle d'entrée sans port (tous les ports ouverts)", [input.metadata.namespace, input.metadata.name])
}

# Chaque règle doit citer le flux de la matrice qu'elle implémente.
deny contains msg if {
	is_netpol
	input.spec.ingress
	not input.metadata.annotations["kalipay.fr/flux"]
	msg := sprintf("%s/%s : annotation kalipay.fr/flux manquante", [input.metadata.namespace, input.metadata.name])
}
