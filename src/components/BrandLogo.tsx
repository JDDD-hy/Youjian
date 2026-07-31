type BrandLogoProps = {
  className?: string;
};

export function BrandLogo({ className = '' }: BrandLogoProps) {
  const src = `${import.meta.env.BASE_URL}youjian-logo.svg`;

  return <img className={className} src={src} alt="" aria-hidden="true" />;
}
