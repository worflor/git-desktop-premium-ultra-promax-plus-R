interface EmptyStateCardProps {
  title: string;
  body: string;
}

export function EmptyStateCard(props: EmptyStateCardProps) {
  return (
    <section class="state-card">
      <h3>{props.title}</h3>
      <p>{props.body}</p>
    </section>
  );
}
