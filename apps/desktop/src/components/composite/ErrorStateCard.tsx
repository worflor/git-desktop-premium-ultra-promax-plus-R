interface ErrorStateCardProps {
  title: string;
  body: string;
}

export function ErrorStateCard(props: ErrorStateCardProps) {
  return (
    <section class="state-card state-card-error" role="alert">
      <h3>{props.title}</h3>
      <p>{props.body}</p>
    </section>
  );
}
