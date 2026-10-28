import type { FastifyError, FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';

// Los mismos de openapi.yaml (components.schemas.ErrorCode); una prueba lo comprueba.
export const errorCodes = [
  'validation_failed',
  'invalid_credentials',
  'unauthenticated',
  'session_expired',
  'csrf_invalid',
  'password_change_required',
  'forbidden',
  'not_found',
  'weak_password',
  'reset_token_invalid',
  'too_many_attempts',
  'payload_too_large',
  'request_rejected',
  'internal_error',
  'service_unavailable',
] as const;

export type ErrorCode = (typeof errorCodes)[number];

export interface FieldError {
  field: string;
  message: string;
}

/** Error esperado que una ruta lanza para responder con un Problem. */
export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    readonly title: string,
    readonly errors?: FieldError[],
  ) {
    super(title);
  }
}

function send(
  request: FastifyRequest,
  reply: FastifyReply,
  status: number,
  code: ErrorCode,
  title: string,
  errors?: FieldError[],
) {
  return reply
    .code(status)
    .type('application/problem+json')
    .send({ type: 'about:blank', title, status, code, requestId: request.id, ...(errors ? { errors } : {}) });
}

const byStatus: Record<number, [ErrorCode, string]> = {
  400: ['validation_failed', 'La petición no es válida'],
  401: ['unauthenticated', 'Hay que iniciar sesión'],
  403: ['forbidden', 'No tienes permiso para esto'],
  404: ['not_found', 'No existe'],
  413: ['payload_too_large', 'La petición es demasiado grande'],
  415: ['validation_failed', 'Tipo de contenido no admitido'],
  429: ['too_many_attempts', 'Demasiados intentos; espera un momento'],
};

/** Errores y 404 como application/problem+json. Un 5xx no expone nada interno. */
export function registerProblemHandlers(app: FastifyInstance): void {
  app.setErrorHandler((err: FastifyError | AppError, request, reply) => {
    if (err instanceof AppError) {
      return send(request, reply, err.status, err.code, err.title, err.errors);
    }
    if (err.validation) {
      const errors = err.validation.map((v) => ({
        field: v.instancePath.replace(/^\//, '').replaceAll('/', '.') || String(v.params?.missingProperty ?? ''),
        message: v.message ?? 'no válido',
      }));
      return send(request, reply, 400, 'validation_failed', 'La petición no es válida', errors);
    }
    const status = err.statusCode ?? 500;
    if (status >= 400 && status < 500) {
      const [code, title] = byStatus[status] ?? ['request_rejected', 'La petición no se pudo atender'];
      return send(request, reply, status, code, title);
    }
    request.log.error({ err }, 'error no controlado');
    return send(request, reply, 500, 'internal_error', 'Algo salió mal; intenta de nuevo');
  });

  app.setNotFoundHandler((request, reply) => send(request, reply, 404, 'not_found', 'No existe'));
}
