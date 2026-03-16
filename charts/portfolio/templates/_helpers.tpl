{{- define "portfolio.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .root.Release.Name }}-{{ .component }}
  labels:
    app: {{ .root.Release.Name }}-{{ .component }}
spec:
  replicas: {{ .values.replicas }}
  selector:
    matchLabels:
      app: {{ .root.Release.Name }}-{{ .component }}
  template:
    metadata:
      labels:
        app: {{ .root.Release.Name }}-{{ .component }}
    spec:
      containers:
        - name: {{ .component }}
          image: "{{ .values.image.repository }}:{{ .values.image.tag }}"
          imagePullPolicy: {{ .values.image.pullPolicy }}
          ports:
            - containerPort: {{ .values.containerPort }}
          readinessProbe:
            httpGet:
              path: {{ .probePath }}
              port: {{ .values.containerPort }}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: {{ .probePath }}
              port: {{ .values.containerPort }}
            initialDelaySeconds: 10
            periodSeconds: 30
          resources:
            requests:
              cpu: {{ .values.resources.requests.cpu }}
              memory: {{ .values.resources.requests.memory }}
            limits:
              cpu: {{ .values.resources.limits.cpu }}
              memory: {{ .values.resources.limits.memory }}
{{- end }}

{{- define "portfolio.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .root.Release.Name }}-{{ .component }}
  labels:
    app: {{ .root.Release.Name }}-{{ .component }}
spec:
  type: ClusterIP
  selector:
    app: {{ .root.Release.Name }}-{{ .component }}
  ports:
    - port: {{ .values.containerPort }}
      targetPort: {{ .values.containerPort }}
      protocol: TCP
{{- end }}
